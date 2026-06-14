import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider, sessionProvider;
import '../../features/shell/shell_branch_provider.dart';
import '../models/trade_purchase_models.dart';
import '../auth/provider_api_guard.dart';
import 'api_read_snapshots.dart';
import 'analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import '../utils/line_display.dart';

/// Alert strip: small cap — full due counts use server-side reports when needed.
const kTradePurchasesAlertFetchLimit = 50;

/// History first page; scroll end loads more via [TradePurchasesListNotifier.loadMore].
const kTradePurchasesHistoryFetchLimit = 100;

String? _purchaseFromApi(DateTime? d) {
  if (d == null) return null;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

@visibleForTesting
({String? from, String? to}) tradePurchaseDateApiRange(
  DateTime? fromDate,
  DateTime? toDate,
) {
  return (
    from: _purchaseFromApi(fromDate),
    to: _purchaseFromApi(toDate),
  );
}

/// Derives API `status` from history chips / route. [null] means unfiltered (`all`).
@visibleForTesting
String? tradeListApiStatusFromFilters(String primaryRaw, String? secondaryRaw) =>
    _tradeListApiStatus(primaryRaw, secondaryRaw);

String? _tradeListApiStatus(String primaryRaw, String? secondaryRaw) {
  final sec = secondaryRaw?.trim().toLowerCase();
  if (sec == 'overdue') return sec;
  if (sec == 'pending') return 'pending';

  final p = primaryRaw.trim().toLowerCase();
  if (p == 'paid') return 'paid';
  if (p == 'draft') return 'draft';
  if (p == 'due_soon') return 'due_soon';
  // `pending_delivery`: client-only filter (same full list as `due`).
  if (p == 'pending_delivery' || p == 'received' || p == 'delivery_stuck') {
    return null;
  }
  // `all`, `due`, and anything else → full list (client filters for `due`).
  return null;
}

/// Bust list + catalog-intel snapshots together.
void invalidateTradePurchaseCaches(dynamic ref) {
  bustTradePurchasesRecentSnapshot(ref);
  ref.invalidate(tradePurchasesListProvider);
  ref.invalidate(tradePurchasesForAlertsProvider);
  ref.invalidate(staffTradePurchasesForAlertsProvider);
  ref.invalidate(tradePurchasesCatalogIntelProvider);
}

/// Same as [invalidateTradePurchaseCaches] for use after async gaps where [WidgetRef] may be disposed.
void invalidateTradePurchaseCachesFromContainer(ProviderContainer container) {
  container.invalidate(tradePurchasesRecentSnapshotProvider);
  container.invalidate(tradePurchasesListProvider);
  container.invalidate(tradePurchasesForAlertsProvider);
  container.invalidate(staffTradePurchasesForAlertsProvider);
  container.invalidate(tradePurchasesCatalogIntelProvider);
}

/// Primary history chip / route filter (client state). Use [_tradeListApiStatus] for API.
final purchaseHistoryPrimaryFilterProvider =
    StateProvider<String>((ref) => 'all');

/// Optional primary sort by bill total (`high` / `low`). When set, overrides date-first ordering except pending-age sorts.
final purchaseHistoryValueSortProvider = StateProvider<String?>((ref) => null);

/// Client-side filter only (not sent to list API — avoids refetch per keystroke).
final purchaseHistorySearchProvider = StateProvider<String>((ref) => '');

/// Desktop purchase history master-detail selection (≥ [kDesktopMin]).
final purchaseSelectedIdProvider = StateProvider<String?>((ref) => null);

/// True while [_PurchaseHistoryFullscreenSearchPage] is mounted so
/// [tradePurchasesListProvider] still loads the history API even if
/// [shellCurrentBranchProvider] is not [ShellBranch.history] (IndexedStack
/// offstage rebuilds, or branch/index briefly out of sync on first frame).
final purchaseHistoryFullscreenSearchActiveProvider =
    StateProvider<bool>((ref) => false);

/// Optional secondary filter: `pending` | `overdue` (client-side; paid uses primary).
final purchaseHistorySecondaryFilterProvider =
    StateProvider<String?>((ref) => null);

/// Advanced filters (sheet). Substrings match supplier/broker names client-side.
final purchaseHistorySortNewestFirstProvider =
    StateProvider<bool>((ref) => true);

/// When true, the list is sorted by **most undelivered days first** (overrides
/// date/value sort — trader workflow: see the oldest pending deliveries at the top).
final purchaseHistoryUndeliveredSortProvider =
    StateProvider<bool>((ref) => false);


final purchaseHistorySupplierContainsProvider =
    StateProvider<String?>((ref) => null);

final purchaseHistoryBrokerContainsProvider =
    StateProvider<String?>((ref) => null);

/// `bag` | `box` | `tin` | `mixed` — client-side only.
final purchaseHistoryPackKindFilterProvider =
    StateProvider<String?>((ref) => null);

final purchaseHistoryDateFromProvider =
    StateProvider<DateTime?>((ref) => null);

final purchaseHistoryDateToProvider =
    StateProvider<DateTime?>((ref) => null);

/// Unfiltered list for due/overdue alert derivation (ignores history tab filters).
final tradePurchasesForAlertsProvider =
    Provider.autoDispose<List<Map<String, dynamic>>?>((ref) {
  if (providerSkipApi(ref)) return const [];
  final branch = ref.watch(shellCurrentBranchProvider);
  if (branch != ShellBranch.home && branch != ShellBranch.history) {
    return const [];
  }
  return ref.watch(tradePurchasesRecentSnapshotProvider).valueOrNull;
});

/// Staff home + deliveries — shares [tradePurchasesRecentSnapshotProvider] SSOT.
final staffTradePurchasesForAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 8), link.close);
  ref.onDispose(t.cancel);
  if (providerSkipApi(ref)) return [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  if (session.primaryBusiness.role.toLowerCase() != 'staff') return [];
  return ref.watch(tradePurchasesRecentSnapshotProvider.future);
});

final staffTradePurchasesForAlertsParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(staffTradePurchasesForAlertsProvider).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});

final tradePurchasesForAlertsParsedProvider =
    Provider.autoDispose<List<TradePurchase>?>((ref) {
  final maps = ref.watch(tradePurchasesForAlertsProvider);
  if (maps == null) return null;
  return maps
      .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

/// Paged trade rows for Purchase History (offset grows via [TradePurchasesListNotifier.loadMore]).
class TradePurchasesListView {
  const TradePurchasesListView({required this.rows, required this.hasMore});

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
}

/// API inputs for history list — client-only chips (e.g. pending_delivery) must not refetch.
@visibleForTesting
String purchaseHistoryListFetchKey({
  required String? apiStatus,
  required String? purchaseFrom,
  required String? purchaseTo,
}) => '${apiStatus ?? ''}|${purchaseFrom ?? ''}|${purchaseTo ?? ''}';

final purchaseHistoryListFetchKeyProvider = Provider.autoDispose<String>((ref) {
  final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
  final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
  final apiStatus = _tradeListApiStatus(primary, secondary);
  final analyticsRange = ref.watch(analyticsDateRangeProvider);
  final advFrom = ref.watch(purchaseHistoryDateFromProvider);
  final advTo = ref.watch(purchaseHistoryDateToProvider);
  final fromDate = advFrom ?? analyticsRange.from;
  final toDate = advTo ?? analyticsRange.to;
  final apiRange = tradePurchaseDateApiRange(fromDate, toDate);
  return purchaseHistoryListFetchKey(
    apiStatus: apiStatus,
    purchaseFrom: apiRange.from,
    purchaseTo: apiRange.to,
  );
});

class TradePurchasesListNotifier extends AutoDisposeAsyncNotifier<TradePurchasesListView> {
  bool _loadMoreBusy = false;

  @override
  Future<TradePurchasesListView> build() async {
    final link = ref.keepAlive();
    final t = Timer(const Duration(minutes: 2), link.close);
    ref.onDispose(t.cancel);

    if (ref.watch(authSessionExpiredProvider)) {
      return const TradePurchasesListView(rows: [], hasMore: false);
    }

    final branch = ref.watch(shellCurrentBranchProvider);
    final fullscreenSearch =
        ref.watch(purchaseHistoryFullscreenSearchActiveProvider);
    if (branch != ShellBranch.history && !fullscreenSearch) {
      return const TradePurchasesListView(rows: [], hasMore: false);
    }

    final session = ref.watch(sessionProvider);
    if (session == null) {
      return const TradePurchasesListView(rows: [], hasMore: false);
    }
    ref.watch(purchaseHistoryListFetchKeyProvider);
    final primary = ref.read(purchaseHistoryPrimaryFilterProvider);
    final secondary = ref.read(purchaseHistorySecondaryFilterProvider);
    final apiStatus = _tradeListApiStatus(primary, secondary);
    final analyticsRange = ref.read(analyticsDateRangeProvider);
    final advFrom = ref.read(purchaseHistoryDateFromProvider);
    final advTo = ref.read(purchaseHistoryDateToProvider);

    final fromDate = advFrom ?? analyticsRange.from;
    final toDate = advTo ?? analyticsRange.to;

    final apiRange = tradePurchaseDateApiRange(fromDate, toDate);

    final page = await ref.read(hexaApiProvider).listTradePurchases(
          businessId: session.primaryBusiness.id,
          limit: kTradePurchasesHistoryFetchLimit,
          offset: 0,
          status: apiStatus,
          purchaseFrom: apiRange.from,
          purchaseTo: apiRange.to,
        );
    final hasMore = page.length >= kTradePurchasesHistoryFetchLimit;
    return TradePurchasesListView(rows: page, hasMore: hasMore);
  }

  /// Appends the next API page when the user scrolls near the end of the list.
  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || _loadMoreBusy) return;
    final branch = ref.read(shellCurrentBranchProvider);
    final fullscreenSearch =
        ref.read(purchaseHistoryFullscreenSearchActiveProvider);
    if (branch != ShellBranch.history && !fullscreenSearch) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final offset = cur.rows.length;
    _loadMoreBusy = true;
    try {
      final primary = ref.read(purchaseHistoryPrimaryFilterProvider);
      final secondary = ref.read(purchaseHistorySecondaryFilterProvider);
      final apiStatus = _tradeListApiStatus(primary, secondary);
      final analyticsRange = ref.read(analyticsDateRangeProvider);
      final advFrom = ref.read(purchaseHistoryDateFromProvider);
      final advTo = ref.read(purchaseHistoryDateToProvider);

      final fromDate = advFrom ?? analyticsRange.from;
      final toDate = advTo ?? analyticsRange.to;

      final apiRange = tradePurchaseDateApiRange(fromDate, toDate);
      final page = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: kTradePurchasesHistoryFetchLimit,
            offset: offset,
            status: apiStatus,
            purchaseFrom: apiRange.from,
            purchaseTo: apiRange.to,
          );
      final after = state.valueOrNull;
      if (after == null || after.rows.length != offset) return;
      if (page.isEmpty) {
        state = AsyncData(TradePurchasesListView(rows: after.rows, hasMore: false));
        return;
      }
      final hasMore = page.length >= kTradePurchasesHistoryFetchLimit;
      state = AsyncData(TradePurchasesListView(
        rows: [...after.rows, ...page],
        hasMore: hasMore,
      ));
    } finally {
      _loadMoreBusy = false;
    }
  }
}

final tradePurchasesListProvider =
    AsyncNotifierProvider.autoDispose<TradePurchasesListNotifier, TradePurchasesListView>(
  TradePurchasesListNotifier.new,
);

/// Parsed rows track [tradePurchasesListProvider] without `await …future`, so
/// async completion cannot call `markNeedsBuild` on a disposed home/shell
/// element after a fast navigation or 401-driven route swap (Riverpod #…).
final tradePurchasesParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesListProvider).whenData(
    (view) {
      final parsed = <TradePurchase>[];
      for (final e in view.rows) {
        try {
          parsed.add(TradePurchase.fromJson(Map<String, dynamic>.from(e)));
        } catch (err, st) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: err,
            stack: st,
            library: 'trade_purchases_provider',
            context: ErrorDescription('parsing TradePurchase row'),
            silent: true,
          ));
        }
      }
      return parsed;
    },
  );
});

/// Counts for dashboard / history banner.
final purchaseAlertsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var dueSoon = 0;
      var overdue = 0;
      var paid = 0;
      var dueToday = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final p in list) {
        final st = p.statusEnum;
        if (st == PurchaseStatus.dueSoon) dueSoon++;
        if (st == PurchaseStatus.overdue) overdue++;
        if (st == PurchaseStatus.paid) paid++;
        if (p.dueDate != null) {
          final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
          if (d == today &&
              st != PurchaseStatus.paid &&
              st != PurchaseStatus.cancelled) {
            dueToday++;
          }
        }
      }
      return {
        'dueSoon': dueSoon,
        'overdue': overdue,
        'paid': paid,
        'dueToday': dueToday,
      };
    },
    orElse: () =>
        {'dueSoon': 0, 'overdue': 0, 'paid': 0, 'dueToday': 0},
  );
});

/// Period strip for Purchase History: aligns with [analyticsDateRangeProvider]
/// (same period as Reports/Home Month preset).
///
/// Uses the **same** parsed rows as the history list whenever that list has
/// resolved ([tradePurchasesParsedProvider]), so KPI chips cannot disagree with
/// visible cards.
///
/// While the main list is still loading, we return [PurchaseHistoryMonthStats.empty]
/// — **not** the small alerts sample. Alerts cap at ~50 rows and can disagree with
/// the full history API (web users saw rich KPIs with a blank list below).
final purchaseHistoryMonthStatsProvider =
    Provider.autoDispose<PurchaseHistoryMonthStats>((ref) {
  final range = ref.watch(analyticsDateRangeProvider);
  final listAsync = ref.watch(tradePurchasesParsedProvider);
  return listAsync.when(
    data: (list) => computePurchaseHistoryRangeStats(
      list,
      from: range.from,
      to: range.to,
    ),
    loading: () => PurchaseHistoryMonthStats.empty,
    error: (_, __) => PurchaseHistoryMonthStats.empty,
  );
});

/// Bags / boxes / tins from loaded trade purchase lines.
final purchaseUnitTotalsProvider =
    Provider.autoDispose<({int bags, int boxes, int tins})>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var bags = 0;
      var boxes = 0;
      var tins = 0;
      for (final p in list) {
        for (final ln in p.lines) {
          final u = ln.unit.toUpperCase();
          final q = ln.qty.round();
          if (unitCountsAsBagFamily(ln.unit)) bags += q;
          if (u.contains('BOX')) boxes += q;
          if (u.contains('TIN')) tins += q;
        }
      }
      return (bags: bags, boxes: boxes, tins: tins);
    },
    orElse: () => (bags: 0, boxes: 0, tins: 0),
  );
});

/// Purchases for one catalog item (item detail / supplier intel) — not full business list.
final tradePurchasesForItemProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, itemId) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 45), keepAlive.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null || itemId.isEmpty) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        catalogItemId: itemId,
        limit: 50,
      );
});

final tradePurchasesForItemParsedProvider =
    Provider.autoDispose.family<AsyncValue<List<TradePurchase>>, String>(
        (ref, itemId) {
  return ref.watch(tradePurchasesForItemProvider(itemId)).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});

/// Trade list for catalog item intel — shares [tradePurchasesRecentSnapshotProvider].
final tradePurchasesCatalogIntelProvider =
    Provider.autoDispose<List<Map<String, dynamic>>?>((ref) {
  if (providerSkipApi(ref)) return const [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return const [];
  return ref.watch(tradePurchasesRecentSnapshotProvider).valueOrNull;
});

final tradePurchasesCatalogIntelParsedProvider =
    Provider.autoDispose<List<TradePurchase>?>((ref) {
  final maps = ref.watch(tradePurchasesCatalogIntelProvider);
  if (maps == null) return null;
  return maps
      .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});
