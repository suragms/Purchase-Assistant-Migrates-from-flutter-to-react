import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'home_dashboard_provider.dart';
import 'trade_report_snapshot_provider.dart';

/// Breakdown view on Home (drives the ring + rows for non-category tabs).
enum HomeBreakdownTab {
  category,
  subcategory,
  supplier,
  items,
}

extension HomeBreakdownTabX on HomeBreakdownTab {
  String get label => switch (this) {
        HomeBreakdownTab.category => 'Category',
        HomeBreakdownTab.subcategory => 'Subcategory',
        HomeBreakdownTab.supplier => 'Supplier',
        HomeBreakdownTab.items => 'Items',
      };
}

/// Selected breakdown tab (Category | Subcategory | Supplier | Items).
final homeBreakdownTabProvider =
    StateProvider<HomeBreakdownTab>((ref) => HomeBreakdownTab.category);

/// Same date window as [homeDashboardDataProvider], from already-watched state.
({String from, String to}) homeDateRangeForWatch(
  HomePeriod period,
  ({DateTime start, DateTime endInclusive})? custom,
) {
  final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
  final lastInclusive = range.end.subtract(const Duration(milliseconds: 1));
  return (
    from: _apiDate(range.start),
    to: _apiDate(lastInclusive),
  );
}

/// `from` / `to` query strings (inclusive `to` day) for Home period — same window as
/// [homeDashboardDataProvider].
({String from, String to}) homeDateRangeForRef(Ref ref) {
  return homeDateRangeForWatch(
    ref.watch(homePeriodProvider),
    ref.watch(homeCustomDateRangeProvider),
  );
}

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Per-tab trade report rows for Home (fetched in parallel; category tab uses snapshot only).
class HomeShellReportsBundle {
  const HomeShellReportsBundle({
    required this.subcategories,
    required this.suppliers,
    required this.items,
  });

  final List<Map<String, dynamic>> subcategories;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> items;

  static const empty = HomeShellReportsBundle(
    subcategories: [],
    suppliers: [],
    items: [],
  );
}

/// When [reportsHomeOverview] includes `home_shell`, reuse it (same DB work as dashboard).
HomeShellReportsBundle? homeShellBundleFromOverviewSnap(
    Map<String, dynamic>? overview) {
  if (overview == null) return null;
  final hs = overview['home_shell'];
  if (hs is! Map) return null;
  return _homeShellFromHive(Map<String, dynamic>.from(hs));
}

HomeShellReportsBundle _homeShellFromHive(Map<String, dynamic>? raw) {
  if (raw == null) return HomeShellReportsBundle.empty;
  List<Map<String, dynamic>> lm(String key) {
    final v = raw[key];
    if (v is! List) return [];
    return v
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  return HomeShellReportsBundle(
    subcategories: lm('subcategories'),
    suppliers: lm('suppliers'),
    items: lm('items'),
  );
}

/// Last persisted home-shell rows for the current period (instant paint on tab switches / reload).
final homeShellReportsSyncCacheProvider =
    Provider.autoDispose<HomeShellReportsBundle?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final q = homeDateRangeForRef(ref);
  final raw = OfflineStore.getCachedHomeShellReports(
    session.primaryBusiness.id,
    q.from,
    q.to,
  );
  if (raw == null) return null;
  return _homeShellFromHive(raw);
});

final Map<String, Future<HomeShellReportsBundle>> _shellInflight = {};

/// Clears shell tab dedupe futures after purchase mutations (see [bustHomeDashboardVolatileCaches]).
void bustHomeShellReportsInflight() {
  _shellInflight.clear();
}

/// connectivity_plus can hang on some devices; never block shell forever.
const _connectivityTimeout = Duration(seconds: 3);

/// Hard cap so [work] always completes (releases [_shellInflight]).
const _shellWorkHardTimeout = Duration(seconds: 42);

/// Types + suppliers + items for the current Home date range.
final homeShellReportsProvider =
    FutureProvider.autoDispose<HomeShellReportsBundle>((ref) async {
  ref.keepAlive();
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return HomeShellReportsBundle.empty;
  }
  if (!shellBranchIsVisible(ref, ShellBranch.home)) {
    return ref.watch(homeShellReportsSyncCacheProvider) ??
        HomeShellReportsBundle.empty;
  }
  final q = homeDateRangeForRef(ref);
  final bid = session.primaryBusiness.id;
  final dedupeKey = '$bid|${q.from}|${q.to}';

  Future<HomeShellReportsBundle> work() async {
    Future<HomeShellReportsBundle> guarded() async {
    final cachedRaw =
        OfflineStore.getCachedHomeShellReports(bid, q.from, q.to);
    // connectivity_plus can throw or misbehave on some browsers; never fail
    // the whole Home shell — assume online and fall back to cache on fetch errors.
    List<ConnectivityResult> reachability;
    try {
      reachability = await Connectivity()
          .checkConnectivity()
          .timeout(_connectivityTimeout);
    } on TimeoutException {
      reachability = const <ConnectivityResult>[ConnectivityResult.other];
    } catch (_) {
      reachability = const <ConnectivityResult>[ConnectivityResult.other];
    }
    final looksOffline = reachability.isEmpty ||
        reachability.every((c) => c == ConnectivityResult.none);
    if (looksOffline) {
      return _homeShellFromHive(cachedRaw);
    }
    try {
      await awaitHomeDashboardInflightIfAny(dedupeKey);
      final fromOverview =
          homeShellBundleFromOverviewSnap(homeOverviewSnapForKey(dedupeKey));
      if (fromOverview != null) {
        if (fromOverview.subcategories.isNotEmpty ||
            fromOverview.suppliers.isNotEmpty ||
            fromOverview.items.isNotEmpty) {
          await OfflineStore.cacheHomeShellReports(
            bid,
            q.from,
            q.to,
            subcategories: fromOverview.subcategories,
            suppliers: fromOverview.suppliers,
            items: fromOverview.items,
          );
        }
        return fromOverview;
      }
      // Per-endpoint timeout + isolation: one slow/hung API does not block others.
      final snap = await fetchTradeReportSnapshot(
        ref,
        (from: q.from, to: q.to),
      );
      final bundle = HomeShellReportsBundle(
        subcategories: snap.types,
        suppliers: snap.suppliers,
        items: snap.items,
      );
      if (bundle.subcategories.isNotEmpty ||
          bundle.suppliers.isNotEmpty ||
          bundle.items.isNotEmpty) {
        await OfflineStore.cacheHomeShellReports(
          bid,
          q.from,
          q.to,
          subcategories: bundle.subcategories,
          suppliers: bundle.suppliers,
          items: bundle.items,
        );
      }
      return bundle;
    } on TimeoutException {
      return _homeShellFromHive(cachedRaw);
    } on DioException {
      return _homeShellFromHive(cachedRaw);
    } catch (_) {
      return _homeShellFromHive(cachedRaw);
    }
    }

    try {
      return await guarded().timeout(_shellWorkHardTimeout);
    } on TimeoutException {
      final cachedRaw =
          OfflineStore.getCachedHomeShellReports(bid, q.from, q.to);
      return _homeShellFromHive(cachedRaw);
    }
  }

  return _shellInflight.putIfAbsent(
    dedupeKey,
    () => work().whenComplete(() => _shellInflight.remove(dedupeKey)),
  );
});

HomeBreakdownTab? homeBreakdownTabFromQuery(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final t in HomeBreakdownTab.values) {
    if (t.name == raw) return t;
  }
  return null;
}
