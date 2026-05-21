import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../api/hexa_api.dart';
import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';
import '../services/offline_store.dart';
import '../utils/line_display.dart';
import '../reporting/trade_report_aggregate.dart';
import 'catalog_providers.dart';

/// Period chips on the home dashboard. [custom] uses
/// [homeCustomDateRangeProvider] (inclusive start/end dates).
enum HomePeriod { today, week, month, year, custom }

extension HomePeriodX on HomePeriod {
  String get label => switch (this) {
        HomePeriod.today => 'Today',
        HomePeriod.week => 'Week',
        HomePeriod.month => 'Month',
        HomePeriod.year => 'Year',
        HomePeriod.custom => 'Custom',
      };
}

/// Optional inclusive date range when [HomePeriod.custom] is selected.
final homeCustomDateRangeProvider =
    StateProvider<({DateTime start, DateTime endInclusive})?>(
  (_) => null,
);

/// Returns the half-open window `[start, end)` in local date space.
({DateTime start, DateTime end}) homePeriodRange(
  HomePeriod p, {
  DateTime? now,
  ({DateTime start, DateTime endInclusive})? custom,
}) {
  final t = now ?? DateTime.now();
  final endOfDay =
      DateTime(t.year, t.month, t.day).add(const Duration(days: 1));
  if (p == HomePeriod.custom && custom != null) {
    final s = DateTime(
      custom.start.year,
      custom.start.month,
      custom.start.day,
    );
    final e = DateTime(
      custom.endInclusive.year,
      custom.endInclusive.month,
      custom.endInclusive.day,
    ).add(const Duration(days: 1));
    return (start: s, end: e);
  }
  return switch (p) {
    HomePeriod.today => (
        start: DateTime(t.year, t.month, t.day),
        end: endOfDay,
      ),
    HomePeriod.week => (
        start:
            DateTime(t.year, t.month, t.day).subtract(const Duration(days: 6)),
        end: endOfDay,
      ),
    // Rolling 30 calendar days through today inclusive (half-open `[start, end)`).
    HomePeriod.month => (
        start: DateTime(t.year, t.month, t.day)
            .subtract(const Duration(days: 29)),
        end: endOfDay,
      ),
    HomePeriod.year => (start: DateTime(t.year, 1, 1), end: endOfDay),
    HomePeriod.custom => (
        start: DateTime(t.year, t.month, 1),
        end: endOfDay,
      ),
  };
}

final homePeriodProvider = StateProvider<HomePeriod>((_) => HomePeriod.month);

class CategoryUnitTotals {
  CategoryUnitTotals({this.bags = 0, this.boxes = 0, this.tins = 0});
  double bags;
  double boxes;
  double tins;

  bool get isEmpty => bags == 0 && boxes == 0 && tins == 0;
}

class CategoryItemStat {
  const CategoryItemStat({
    required this.name,
    required this.qty,
    required this.unit,
    required this.amount,
    this.catalogItemId,
  });

  final String name;
  final double qty;
  final String unit;
  final double amount;
  final String? catalogItemId;
}

class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.totalQty,
    required this.units,
    required this.items,
    this.subtitleSupplier,
    this.subtitleBroker,
  });

  final String categoryId;
  final String categoryName;
  final double totalAmount;
  final double totalQty;
  final CategoryUnitTotals units;
  /// Sorted by amount (desc) — first is the category top item.
  final List<CategoryItemStat> items;
  final String? subtitleSupplier;
  final String? subtitleBroker;
}

/// One row in the “Subcategory” (CategoryType) view — `label` is e.g. "Rice — Biriyani".
class SubcategoryStat {
  const SubcategoryStat({
    required this.id,
    required this.label,
    required this.totalAmount,
    required this.totalQty,
  });

  final String id;
  final String label;
  final double totalAmount;
  final double totalQty;
}

/// One slice/row in the “Items” donut and breakdown list.
class ItemSliceStat {
  const ItemSliceStat({
    required this.name,
    this.catalogItemId,
    required this.totalAmount,
    required this.totalQty,
    required this.unit,
  });

  final String name;
  final String? catalogItemId;
  final double totalAmount;
  final double totalQty;
  final String unit;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.period,
    required this.totalPurchase,
    required this.totalQtyAllLines,
    required this.totalKg,
    required this.totalBags,
    required this.totalBoxes,
    required this.totalTins,
    required this.purchaseCount,
    required this.categories,
    required this.subcategories,
    required this.itemSlices,
    this.totalLanding = 0,
    this.totalSelling = 0,
    this.totalProfit = 0,
    this.profitPercent,
    this.pendingDeliveryCount = 0,
  });

  final HomePeriod period;
  final double totalPurchase;
  /// Landing (purchase) side total; matches [totalLanding] when the API sends it.
  final double totalLanding;
  final double totalSelling;
  final double totalProfit;
  final double? profitPercent;
  /// Sum of line `qty` in range (for display next to purchase count).
  final double totalQtyAllLines;
  final double totalKg;
  final double totalBags;
  final double totalBoxes;
  final double totalTins;
  final int purchaseCount;
  final List<CategoryStat> categories;
  final List<SubcategoryStat> subcategories;
  final List<ItemSliceStat> itemSlices;
  /// Purchases not marked delivered (excludes deleted/cancelled); from API summary.
  final int pendingDeliveryCount;

  bool get isEmpty => purchaseCount == 0;

  static const empty = HomeDashboardData(
    period: HomePeriod.month,
    totalPurchase: 0,
    totalLanding: 0,
    totalSelling: 0,
    totalProfit: 0,
    profitPercent: null,
    totalQtyAllLines: 0,
    totalKg: 0,
    totalBags: 0,
    totalBoxes: 0,
    totalTins: 0,
    purchaseCount: 0,
    categories: [],
    subcategories: [],
    itemSlices: [],
    pendingDeliveryCount: 0,
  );
}

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Server-side trade report snapshot (line amounts + [trade_query] statuses) for one date window.
HomeDashboardData homeDashboardDataFromApiSnapshot(
  HomePeriod period,
  Map<String, dynamic> snap,
) {
  final clean = Map<String, dynamic>.from(snap)
    ..remove('degraded')
    ..remove('degraded_reason');
  final summary =
      (clean['summary'] is Map) ? clean['summary']! as Map : const {};
  final unitTotals = (clean['unit_totals'] is Map)
      ? clean['unit_totals']! as Map
      : const {};
  final deals = (summary['deals'] as num?)?.toInt() ?? 0;
  final totalPurchase = (summary['total_purchase'] as num?)?.toDouble() ?? 0.0;
  final totalLanding = (summary['total_landing'] as num?)?.toDouble() ?? totalPurchase;
  final totalSelling = (summary['total_selling'] as num?)?.toDouble() ?? 0.0;
  final totalProfit = (summary['total_profit'] as num?)?.toDouble() ??
      (totalSelling - totalLanding);
  final profitPercent = (summary['profit_percent'] as num?)?.toDouble();
  final pendingDeliveryCount =
      (summary['pending_delivery_count'] as num?)?.toInt() ?? 0;
  final totalQtyAllLines = (summary['total_qty'] as num?)?.toDouble() ?? 0.0;
  final totalKg = (unitTotals['total_kg'] as num?)?.toDouble() ?? 0.0;
  final totalBags = (unitTotals['total_bags'] as num?)?.toDouble() ?? 0.0;
  final totalBoxes = (unitTotals['total_boxes'] as num?)?.toDouble() ?? 0.0;
  final totalTins = (unitTotals['total_tins'] as num?)?.toDouble() ?? 0.0;

  final rawCats = clean['categories'];
  final categories = <CategoryStat>[];
  if (rawCats is List) {
    for (final c in rawCats) {
      if (c is! Map) continue;
      final m = Map<String, dynamic>.from(c);
      final u = m['units'];
      final umap = u is Map ? Map<String, dynamic>.from(u) : const {};
      final itemRows = <CategoryItemStat>[];
      final items = m['items'];
      if (items is List) {
        for (final it in items) {
          if (it is! Map) continue;
          final im = Map<String, dynamic>.from(it);
          final cid = im['catalog_item_id']?.toString();
          itemRows.add(
            CategoryItemStat(
              name: im['name']?.toString() ?? '—',
              qty: (im['qty'] as num?)?.toDouble() ?? 0.0,
              unit: im['unit']?.toString() ?? '—',
              amount: (im['amount'] as num?)?.toDouble() ?? 0.0,
              catalogItemId: (cid != null && cid.isNotEmpty) ? cid : null,
            ),
          );
        }
      }
      itemRows.sort((a, b) => b.amount.compareTo(a.amount));
      categories.add(
        CategoryStat(
          categoryId: m['category_id']?.toString() ?? '_uncat',
          categoryName: m['category_name']?.toString() ?? 'Uncategorised',
          totalAmount: (m['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (m['total_qty'] as num?)?.toDouble() ?? 0.0,
          units: CategoryUnitTotals(
            bags: (umap['bags'] as num?)?.toDouble() ?? 0.0,
            boxes: (umap['boxes'] as num?)?.toDouble() ?? 0.0,
            tins: (umap['tins'] as num?)?.toDouble() ?? 0.0,
          ),
          items: itemRows,
          subtitleSupplier: m['subtitle_supplier']?.toString(),
          subtitleBroker: m['subtitle_broker']?.toString(),
        ),
      );
    }
  }
  categories.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final subcategories = <SubcategoryStat>[];
  final rawTypes = clean['subcategories'];
  if (rawTypes is List) {
    for (final t in rawTypes) {
      if (t is! Map) continue;
      final tm = Map<String, dynamic>.from(t);
      final cat = tm['category_name']?.toString() ?? '';
      final tname = tm['type_name']?.toString() ?? '';
      final label = tname.isEmpty ? '$cat — No type' : '$cat — $tname';
      final id = '$cat|${tm['type_name'] ?? 'none'}';
      subcategories.add(
        SubcategoryStat(
          id: id,
          label: label,
          totalAmount: (tm['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (tm['total_qty'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }
  }
  subcategories.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final itemSlices = <ItemSliceStat>[];
  final rawItems = clean['item_slices'];
  if (rawItems is List) {
    for (final it in rawItems) {
      if (it is! Map) continue;
      final im = Map<String, dynamic>.from(it);
      itemSlices.add(
        ItemSliceStat(
          name: im['item_name']?.toString() ?? '—',
          catalogItemId: im['catalog_item_id']?.toString(),
          totalAmount: (im['total_purchase'] as num?)?.toDouble() ?? 0.0,
          totalQty: (im['total_qty'] as num?)?.toDouble() ?? 0.0,
          unit: im['unit']?.toString() ?? '—',
        ),
      );
    }
  }
  itemSlices.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  return HomeDashboardData(
    period: period,
    totalPurchase: totalPurchase,
    totalLanding: totalLanding,
    totalSelling: totalSelling,
    totalProfit: totalProfit,
    profitPercent: profitPercent,
    totalQtyAllLines: totalQtyAllLines,
    totalKg: totalKg,
    totalBags: totalBags,
    totalBoxes: totalBoxes,
    totalTins: totalTins,
    purchaseCount: deals,
    categories: categories,
    subcategories: subcategories,
    itemSlices: itemSlices,
    pendingDeliveryCount: pendingDeliveryCount,
  );
}

bool _snapshotHasTradeActivity(HomeDashboardData d) =>
    d.purchaseCount > 0 || d.totalPurchase.abs() > 1e-9;

/// Inclusive local-day filter consistent with [_aggregate] purchase window `[start,end)`.
bool _purchaseInInclusiveLocalRange(
  DateTime purchaseDate,
  DateTime from,
  DateTime toInclusive,
) {
  final pd = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(toInclusive.year, toInclusive.month, toInclusive.day);
  return !pd.isBefore(a) && !pd.isAfter(b);
}

/// Last persisted trade-dashboard snapshot for the current period (instant paint).
final homeDashboardSyncCacheProvider =
    Provider.autoDispose<HomeDashboardData?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final period = ref.watch(homePeriodProvider);
  final custom = ref.watch(homeCustomDateRangeProvider);
  final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
  final lastInclusive = range.end.subtract(const Duration(milliseconds: 1));
  final from = _apiDate(range.start);
  final to = _apiDate(lastInclusive);
  final raw = OfflineStore.getCachedTradeDashboardSnapshot(
    session.primaryBusiness.id,
    from,
    to,
  );
  if (raw == null) return null;
  try {
    return homeDashboardDataFromApiSnapshot(period, raw);
  } catch (_) {
    return null;
  }
});

Future<List<TradePurchase>> _fetchTradePurchasesForHomeRange({
  required HexaApi api,
  required String businessId,
  required DateTime from,
  required DateTime toInclusive,
}) async {
  const limit = 500;
  final out = <TradePurchase>[];
  final seen = <String>{};
  final purchaseFrom = _apiDate(from);
  final purchaseTo = _apiDate(toInclusive);
  for (var offset = 0; offset < 50000; offset += limit) {
    final raw = await api.listTradePurchases(
      businessId: businessId,
      limit: limit,
      offset: offset,
      status: 'all',
      purchaseFrom: purchaseFrom,
      purchaseTo: purchaseTo,
    );
    if (raw.isEmpty) break;
    for (final e in raw) {
      try {
        final p = TradePurchase.fromJson(Map<String, dynamic>.from(e as Map));
        if (p.id.isEmpty) continue;
        if (!_purchaseInInclusiveLocalRange(
              p.purchaseDate,
              from,
              toInclusive,
            )) {
          continue;
        }
        if (seen.add(p.id)) out.add(p);
      } catch (_) {}
    }
    if (raw.length < limit) break;
  }
  return out;
}

/// Server fetch outcome for Home — always completes with data (possibly cached).
class HomeDashboardPayload {
  const HomeDashboardPayload({
    required this.data,
    this.banner,
    this.persistAlert = false,
    this.stale = false,
  });

  final HomeDashboardData data;
  final String? banner;
  final bool persistAlert;
  /// True when [data] was served from memory/disk before a fresh network response.
  final bool stale;
}

class _DashboardFailureStats {
  static final Map<String, int> _s = {};

  static int bump(String k) {
    final n = (_s[k] ?? 0) + 1;
    _s[k] = n;
    return n;
  }

  static void reset(String k) => _s.remove(k);
}

final Map<String, Future<HomeDashboardPayload>> _dashInflight = {};

/// Lets [homeShellReportsProvider] wait for the same in-flight overview and reuse `home_shell`.
Future<void> awaitHomeDashboardInflightIfAny(String dedupeKey) async {
  final f = _dashInflight[dedupeKey];
  if (f != null) {
    try {
      await f;
    } catch (_) {}
  }
}

/// Raw overview JSON for a date key (includes `home_shell` when requested from API).
Map<String, dynamic>? homeOverviewSnapForKey(String dedupeKey) =>
    _homeOverviewSnapMemory[dedupeKey];

int _homeDashBustGeneration = 0;

String _mapDashboardDioBanner(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Server waking up...';
    case DioExceptionType.connectionError:
      return 'No connection';
    default:
      break;
  }
  final sc = e.response?.statusCode;
  if (sc == 503) {
    final h = e.response?.headers.value('x-database-unavailable');
    if (h == '1') {
      return 'Database temporarily unavailable';
    }
    return 'Service temporarily unavailable';
  }
  if (sc != null && sc >= 500) return 'Temporary server issue';
  return 'Updating data...';
}

String _dashMemKey(String bid, String from, String to) => '$bid|$from|$to';

final Map<String, Map<String, dynamic>> _homeOverviewSnapMemory = {};

/// Clears in-flight fetches and RAM snapshots for [reportsHomeOverview] home aggregates.
/// Call before invalidating [homeDashboardDataProvider] after purchase mutations so a
/// concurrent request cannot resurrect pre-delete totals via [putIfAbsent] dedupe.
void bustHomeDashboardVolatileCaches() {
  _homeDashBustGeneration++;
  _dashInflight.clear();
  _homeOverviewSnapMemory.clear();
}

/// Thrown when [bustHomeDashboardVolatileCaches] ran while a fetch was in flight;
/// the notifier will invalidate and schedule a fresh pull.
class StaleHomeDashboardFetch implements Exception {
  StaleHomeDashboardFetch();
}

List<Map<String, dynamic>> _coerceJsonMapList(Object? v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map<String, dynamic>) e
      else if (e is Map) Map<String, dynamic>.from(e),
  ];
}

Future<void> _persistHomeShellFromOverviewSnap({
  required String bid,
  required String from,
  required String to,
  required Map<String, dynamic> snap,
}) async {
  final raw = snap['home_shell'];
  if (raw is! Map) return;
  final m = Map<String, dynamic>.from(raw);
  final sub = _coerceJsonMapList(m['subcategories']);
  final sup = _coerceJsonMapList(m['suppliers']);
  final it = _coerceJsonMapList(m['items']);
  if (sub.isEmpty && sup.isEmpty && it.isEmpty) return;
  await OfflineStore.cacheHomeShellReports(
    bid,
    from,
    to,
    subcategories: sub,
    suppliers: sup,
    items: it,
  );
}

/// Server snapshot holder + outstanding refresh flag (SWR-friendly).
class HomeDashboardDashState {
  const HomeDashboardDashState({
    required this.snapshot,
    required this.refreshing,
  });

  final HomeDashboardPayload snapshot;
  /// True until the current [_dashInflight] attempt finishes or short-circuits offline.
  final bool refreshing;
}

Future<HomeDashboardPayload> _homeDashboardPullFresh({
  required Ref ref,
  required String dedupeKey,
  required int bustGenerationAtStart,
  required HexaApi api,
  required HomePeriod period,
  required ({DateTime start, DateTime endInclusive})? custom,
  required String bid,
  required String from,
  required String to,
  required DateTime rangeStart,
  required DateTime lastInclusive,
}) async {
  HomeDashboardPayload ok(
    HomeDashboardData d, {
    String? readDegradedBanner,
    bool readDegraded = false,
  }) {
    _DashboardFailureStats.reset(dedupeKey);
    return HomeDashboardPayload(
      data: d,
      banner: readDegradedBanner,
      stale: readDegraded,
    );
  }

  HomeDashboardData? readCache() {
    final raw = OfflineStore.getCachedTradeDashboardSnapshot(bid, from, to);
    if (raw == null) return null;
    try {
      return homeDashboardDataFromApiSnapshot(period, raw);
    } catch (_) {
      return null;
    }
  }

  final cachedData = readCache();

  List<ConnectivityResult> reachability;
  try {
    reachability = await Connectivity()
        .checkConnectivity()
        .timeout(const Duration(seconds: 3));
  } on TimeoutException {
    reachability = const <ConnectivityResult>[ConnectivityResult.other];
  } catch (_) {
    reachability = const <ConnectivityResult>[ConnectivityResult.other];
  }
  final looksOffline = reachability.isEmpty ||
      reachability.every((c) => c == ConnectivityResult.none);
  if (looksOffline) {
    if (cachedData != null) {
      return HomeDashboardPayload(
        data: cachedData,
        banner: 'No connection — showing last data',
        stale: true,
      );
    }
    return const HomeDashboardPayload(
      data: HomeDashboardData.empty,
      banner: 'No connection',
    );
  }

  // Cold path only: health wake-up adds serial latency + CORS preflight on web.
  // Skip when we have cache (background refresh) or on Flutter web (go straight to
  // reportsHomeOverview; Dio retries handle cold Render).
  if (cachedData == null && !kIsWeb) {
    Future<void> healthPreflightBestEffort() async {
      for (var attempt = 0; attempt <= 2; attempt++) {
        try {
          await api.health();
          return;
        } catch (e) {
          if (e is DioException &&
              e.type == DioExceptionType.connectionError) {
            return;
          }
          if (kDebugMode && attempt < 2) {
            debugPrint('homeDashboard: health preflight retry ${attempt + 1}/2');
          }
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    }

    await healthPreflightBestEffort();
  }

  if (bustGenerationAtStart != _homeDashBustGeneration) {
    throw StaleHomeDashboardFetch();
  }

  try {
    final overviewSw = Stopwatch()..start();
    final snap = await api
        .reportsHomeOverview(
          businessId: bid,
          from: from,
          to: to,
          compact: true,
          shellBundle: true,
        )
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException('reportsHomeOverview'),
        );
    if (kDebugMode) {
      debugPrint(
        'homeDashboard: reportsHomeOverview ${overviewSw.elapsedMilliseconds}ms '
        '($from..$to)',
      );
    }
    if (bustGenerationAtStart != _homeDashBustGeneration) {
      throw StaleHomeDashboardFetch();
    }
    final readDegraded = snap['degraded'] == true;
    final readDegradedBanner =
        readDegraded ? 'Showing last data — refresh delayed' : null;
    await OfflineStore.cacheTradeDashboardSnapshot(
      bid,
      from,
      to,
      Map<String, dynamic>.from(snap),
    );
    _homeOverviewSnapMemory[dedupeKey] = Map<String, dynamic>.from(snap);
    await _persistHomeShellFromOverviewSnap(
      bid: bid,
      from: from,
      to: to,
      snap: snap,
    );

    final fromSnapshot = homeDashboardDataFromApiSnapshot(period, snap);
    if (_snapshotHasTradeActivity(fromSnapshot)) {
      return ok(
        fromSnapshot,
        readDegradedBanner: readDegradedBanner,
        readDegraded: readDegraded,
      );
    }

    final purchases = await _fetchTradePurchasesForHomeRange(
      api: api,
      businessId: bid,
      from: rangeStart,
      toInclusive: lastInclusive,
    );
    if (bustGenerationAtStart != _homeDashBustGeneration) {
      throw StaleHomeDashboardFetch();
    }
    if (purchases.isEmpty) {
      return ok(
        fromSnapshot,
        readDegradedBanner: readDegradedBanner,
        readDegraded: readDegraded,
      );
    }

    List<Map<String, dynamic>> items;
    List<Map<String, dynamic>> categories;
    try {
      final pair = await Future.wait([
        ref.read(catalogItemsListProvider.future),
        ref.read(itemCategoriesListProvider.future),
      ]);
      items = List<Map<String, dynamic>>.from(pair[0] as List);
      categories = List<Map<String, dynamic>>.from(pair[1] as List);
    } catch (_) {
      final pair = await Future.wait([
        api.listCatalogItems(businessId: bid),
        api.listItemCategories(businessId: bid),
      ]);
      items = pair[0];
      categories = pair[1];
    }
    return ok(
      aggregateHomeDashboard(
        period: period,
        purchases: purchases,
        items: items,
        categories: categories,
        now: DateTime.now(),
        custom: custom,
        pendingDeliveryCount: fromSnapshot.pendingDeliveryCount,
      ),
      readDegradedBanner: readDegradedBanner,
      readDegraded: readDegraded,
    );
  } on TimeoutException catch (_) {
    final streak = _DashboardFailureStats.bump(dedupeKey);
    if (cachedData != null) {
      return HomeDashboardPayload(
        data: cachedData,
        banner: 'Dashboard request timed out — showing last data',
        persistAlert: streak >= 3,
        stale: true,
      );
    }
    return HomeDashboardPayload(
      data: HomeDashboardData.empty,
      banner: 'Dashboard load timed out — try again',
      persistAlert: streak >= 3,
    );
  } on DioException catch (e) {
    final streak = _DashboardFailureStats.bump(dedupeKey);
    if (cachedData != null) {
      return HomeDashboardPayload(
        data: cachedData,
        banner: '${_mapDashboardDioBanner(e)} — showing last data',
        persistAlert: streak >= 3,
        stale: true,
      );
    }
    return HomeDashboardPayload(
      data: HomeDashboardData.empty,
      banner: _mapDashboardDioBanner(e),
      persistAlert: streak >= 3,
    );
  } catch (_) {
    final streak = _DashboardFailureStats.bump(dedupeKey);
    if (cachedData != null) {
      return HomeDashboardPayload(
        data: cachedData,
        banner: 'Offline mode — showing last data',
        persistAlert: streak >= 3,
        stale: true,
      );
    }
    return HomeDashboardPayload(
      data: HomeDashboardData.empty,
      banner: 'Temporary server issue',
      persistAlert: streak >= 3,
    );
  }
}

HomeDashboardPayload? _snapshotPayloadFromStoredJson(
  HomePeriod period,
  Map<String, dynamic> raw,
) {
  try {
    return HomeDashboardPayload(
      data: homeDashboardDataFromApiSnapshot(period, raw),
      stale: true,
    );
  } catch (_) {
    return null;
  }
}

/// Aggregated snapshot: server [reportsHomeOverview] (+ compact trim) — bundled home read path.
///
/// To match Analytics KPI for a period, align calendar `from`/`to` with
/// the analytics date range in `lib/core/providers/analytics_kpi_provider.dart`.
final homeDashboardDataProvider =
    NotifierProvider.autoDispose<HomeDashboardDataNotifier, HomeDashboardDashState>(
  HomeDashboardDataNotifier.new,
);

class HomeDashboardDataNotifier extends AutoDisposeNotifier<HomeDashboardDashState> {
  bool _dead = false;

  @override
  HomeDashboardDashState build() {
    ref.keepAlive();
    _dead = false;
    ref.onDispose(() => _dead = true);
    final period = ref.watch(homePeriodProvider);
    final custom = ref.watch(homeCustomDateRangeProvider);
    final session = ref.watch(sessionProvider);

    if (session == null) {
      return const HomeDashboardDashState(
        snapshot: HomeDashboardPayload(data: HomeDashboardData.empty),
        refreshing: false,
      );
    }

    final bid = session.primaryBusiness.id;
    final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
    final lastInclusive = range.end.subtract(const Duration(milliseconds: 1));
    final from = _apiDate(range.start);
    final to = _apiDate(lastInclusive);
    final dedupeKey = _dashMemKey(bid, from, to);

    final memRaw = _homeOverviewSnapMemory[dedupeKey];
    HomeDashboardPayload? hydrated;
    if (memRaw != null) {
      hydrated = _snapshotPayloadFromStoredJson(period, memRaw);
    }
    hydrated ??= () {
      final raw = OfflineStore.getCachedTradeDashboardSnapshot(bid, from, to);
      return raw != null ? _snapshotPayloadFromStoredJson(period, raw) : null;
    }();

    final seed =
        hydrated ?? const HomeDashboardPayload(data: HomeDashboardData.empty);

    final onHomeTab = shellBranchIsVisible(ref, ShellBranch.home);
    if (!onHomeTab) {
      return HomeDashboardDashState(
        snapshot: seed,
        refreshing: false,
      );
    }

    Future<void>.microtask(() async {
      try {
        final bustAtStart = _homeDashBustGeneration;
        final payload = await _dashInflight.putIfAbsent(
          dedupeKey,
          () => _homeDashboardPullFresh(
                ref: ref,
                dedupeKey: dedupeKey,
                bustGenerationAtStart: bustAtStart,
                api: ref.read(hexaApiProvider),
                period: period,
                custom: custom,
                bid: bid,
                from: from,
                to: to,
                rangeStart: range.start,
                lastInclusive: lastInclusive,
              ).whenComplete(() => _dashInflight.remove(dedupeKey)),
        );
        if (_dead) return;
        state = HomeDashboardDashState(snapshot: payload, refreshing: false);
      } on StaleHomeDashboardFetch {
        if (!_dead) {
          ref.invalidate(homeDashboardDataProvider);
        }
      } catch (_) {
        if (_dead) return;
        // Never leave `refreshing: true` — empty catch used to strand the shell spinner.
        state = HomeDashboardDashState(snapshot: seed, refreshing: false);
      }
    });

    // Only show the top progress / shell skeleton when we have no snapshot to
    // render yet. If memory or Hive already has this range, refresh in the
    // background without flashing loaders on every provider rebuild.
    final hasRenderableCache = hydrated != null;
    if (!hasRenderableCache) {
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (_dead) return;
        if (state.refreshing) {
          state = HomeDashboardDashState(
            snapshot: state.snapshot,
            refreshing: false,
          );
        }
      });
    }
    return HomeDashboardDashState(
      snapshot: seed,
      refreshing: !hasRenderableCache,
    );
  }

  /// Safety valve: force-clear the refreshing flag after a UI timeout.
  void forceStopRefreshing() {
    if (_dead) return;
    if (!state.refreshing) return;
    state = HomeDashboardDashState(
      snapshot: state.snapshot,
      refreshing: false,
    );
  }
}
HomeDashboardData aggregateHomeDashboard({
  required HomePeriod period,
  required List<TradePurchase> purchases,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> categories,
  DateTime? now,
  ({DateTime start, DateTime endInclusive})? custom,
  int pendingDeliveryCount = 0,
}) {
  final range = homePeriodRange(period, now: now, custom: custom);
  return _aggregate(
    period: period,
    purchases: purchases,
    items: items,
    categories: categories,
    rangeStart: range.start,
    rangeEnd: range.end,
    pendingDeliveryCount: pendingDeliveryCount,
  );
}

/// Matches backend `_trade_line_amount_expr`: weight lines use qty × kg_per_unit × landing_cost_per_kg.
double _lineTradeAmount(TradePurchaseLine ln) {
  final kpu = ln.kgPerUnit;
  final lcpk = ln.landingCostPerKg;
  if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
    return ln.qty * kpu * lcpk;
  }
  return ln.qty * ln.landingCost;
}

double _lineKg(TradePurchaseLine ln) {
  if (ln.kgPerUnit != null &&
      ln.kgPerUnit! > 0 &&
      ln.landingCostPerKg != null &&
      ln.landingCostPerKg! > 0) {
    return ln.qty * ln.kgPerUnit!;
  }
  final u = ln.unit.toUpperCase().trim();
  if (u == 'KG' || u.endsWith('KG')) return ln.qty;
  if (unitCountsAsBagFamily(ln.unit)) {
    final k = ln.defaultKgPerBag ?? ln.kgPerUnit;
    if (k != null && k > 0) return ln.qty * k;
  }
  return 0;
}

HomeDashboardData _aggregate({
  required HomePeriod period,
  required List<TradePurchase> purchases,
  required List<Map<String, dynamic>> items,
  required List<Map<String, dynamic>> categories,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  int pendingDeliveryCount = 0,
}) {
  final itemById = <String, Map<String, dynamic>>{
    for (final m in items)
      if (m['id'] != null) m['id'].toString(): m,
  };
  final catNameById = <String, String>{
    for (final c in categories)
      if (c['id'] != null)
        c['id'].toString(): (c['name']?.toString() ?? 'Uncategorised'),
  };

  var totalPurchase = 0.0;
  var totalSelling = 0.0;
  var totalQtyAllLines = 0.0;
  var totalKg = 0.0;
  var totalBags = 0.0;
  var totalBoxes = 0.0;
  var totalTins = 0.0;
  var purchaseCount = 0;

  final catAgg = <String, _CatAgg>{};
  final typeAgg = <String, _TypeAgg>{};
  final globalItem = <String, _ItemAgg>{};

  for (final p in purchases) {
    final st = p.statusEnum;
    if (st == PurchaseStatus.deleted || st == PurchaseStatus.cancelled) {
      continue;
    }
    if (p.purchaseDate.isBefore(rangeStart) ||
        !p.purchaseDate.isBefore(rangeEnd)) {
      continue;
    }

    purchaseCount++;
    totalPurchase += p.totalAmount;

    for (final ln in p.lines) {
      final amt = _lineTradeAmount(ln);
      final sc = ln.sellingCost;
      if (sc != null) {
        totalSelling += ln.qty * sc;
      }
      totalQtyAllLines += ln.qty;
      totalKg += _lineKg(ln);

      final eff = reportEffectivePack(ln);
      if (eff != null) {
        switch (eff.kind) {
          case ReportPackKind.bag:
            totalBags += eff.packQty;
          case ReportPackKind.box:
            totalBoxes += eff.packQty;
          case ReportPackKind.tin:
            totalTins += eff.packQty;
        }
      } else {
        final u = ln.unit.toUpperCase();
        if (u.contains('BAG')) totalBags += ln.qty;
        if (u.contains('BOX')) totalBoxes += ln.qty;
        if (u.contains('TIN')) totalTins += ln.qty;
      }

      String catId = '_uncat';
      String catName = 'Uncategorised';
      final ci = ln.catalogItemId;
      final Map<String, dynamic>? item =
          (ci != null && ci.isNotEmpty) ? itemById[ci] : null;
      if (item != null) {
        final cid = item['category_id']?.toString();
        if (cid != null && cid.isNotEmpty) {
          catId = cid;
          catName = catNameById[cid] ?? 'Uncategorised';
        }
      }
      final tid = item?['type_id']?.toString() ?? 'none';
      final typeKey = '$catId|$tid';
      final tname = (item?['type_name']?.toString() ?? '').trim();
      final typeLabel = item == null
          ? 'Uncategorised'
          : (tname.isEmpty ? '$catName — No type' : '$catName — $tname');
      typeAgg
          .putIfAbsent(
            typeKey,
            () => _TypeAgg(id: typeKey, label: typeLabel),
          )
          .add(amt, ln.qty);

      final agg = catAgg.putIfAbsent(
        catId,
        () => _CatAgg(id: catId, name: catName),
      );
      agg.totalAmount += amt;
      agg.totalQty += ln.qty;

      if (eff != null) {
        switch (eff.kind) {
          case ReportPackKind.bag:
            agg.units.bags += eff.packQty;
          case ReportPackKind.box:
            agg.units.boxes += eff.packQty;
          case ReportPackKind.tin:
            agg.units.tins += eff.packQty;
        }
      } else {
        final u = ln.unit.toUpperCase();
        if (unitCountsAsBagFamily(ln.unit)) agg.units.bags += ln.qty;
        if (u.contains('BOX')) agg.units.boxes += ln.qty;
        if (u.contains('TIN')) agg.units.tins += ln.qty;
      }

      final itemKey = ln.itemName.trim().isEmpty ? '—' : ln.itemName.trim();
      final slot = agg.itemMap.putIfAbsent(
        itemKey,
        () => _ItemAgg(name: itemKey, unit: ln.unit),
      );
      slot.qty += ln.qty;
      slot.amount += amt;
      if (ci != null && ci.isNotEmpty) slot.catalogItemId ??= ci;

      final gk = (ci != null && ci.isNotEmpty) ? 'id:$ci' : 'n:$itemKey';
      final g = globalItem.putIfAbsent(
        gk,
        () => _ItemAgg(name: itemKey, unit: ln.unit),
      );
      g.qty += ln.qty;
      g.amount += amt;
      if (ci != null && ci.isNotEmpty) g.catalogItemId ??= ci;
    }
  }

  final cats = <CategoryStat>[];
  for (final a in catAgg.values) {
    final itemRows = <CategoryItemStat>[];
    for (final it in a.itemMap.values) {
      if (it.qty <= 0 && it.amount <= 0) continue;
      itemRows.add(CategoryItemStat(
        name: it.name,
        qty: it.qty,
        unit: it.unit,
        amount: it.amount,
        catalogItemId: it.catalogItemId,
      ));
    }
    itemRows.sort((x, y) => y.amount.compareTo(x.amount));
    cats.add(CategoryStat(
      categoryId: a.id,
      categoryName: a.name,
      totalAmount: a.totalAmount,
      totalQty: a.totalQty,
      units: a.units,
      items: itemRows,
    ));
  }
  cats.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final subRows = <SubcategoryStat>[];
  for (final t in typeAgg.values) {
    if (t.totalAmount <= 0) continue;
    subRows.add(SubcategoryStat(
      id: t.id,
      label: t.label,
      totalAmount: t.totalAmount,
      totalQty: t.totalQty,
    ));
  }
  subRows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final itemRows = <ItemSliceStat>[];
  for (final it in globalItem.values) {
    if (it.qty <= 0 && it.amount <= 0) continue;
    itemRows.add(ItemSliceStat(
      name: it.name,
      catalogItemId: it.catalogItemId,
      totalAmount: it.amount,
      totalQty: it.qty,
      unit: it.unit,
    ));
  }
  itemRows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

  final totalLanding = totalPurchase;
  final totalProfit = totalSelling - totalLanding;
  final profitPercent =
      totalLanding > 1e-9 ? (totalProfit / totalLanding) * 100.0 : null;
  return HomeDashboardData(
    period: period,
    totalPurchase: totalPurchase,
    totalLanding: totalLanding,
    totalSelling: totalSelling,
    totalProfit: totalProfit,
    profitPercent: profitPercent,
    totalQtyAllLines: totalQtyAllLines,
    totalKg: totalKg,
    totalBags: totalBags,
    totalBoxes: totalBoxes,
    totalTins: totalTins,
    purchaseCount: purchaseCount,
    categories: cats,
    subcategories: subRows,
    itemSlices: itemRows,
    pendingDeliveryCount: pendingDeliveryCount,
  );
}

class _CatAgg {
  _CatAgg({required this.id, required this.name});
  final String id;
  final String name;
  double totalAmount = 0;
  double totalQty = 0;
  final CategoryUnitTotals units = CategoryUnitTotals();
  final Map<String, _ItemAgg> itemMap = {};
}

class _ItemAgg {
  _ItemAgg({required this.name, required this.unit});
  final String name;
  final String unit;
  String? catalogItemId;
  double qty = 0;
  double amount = 0;
}

class _TypeAgg {
  _TypeAgg({required this.id, required this.label});
  final String id;
  final String label;
  double totalAmount = 0;
  double totalQty = 0;

  void add(double amt, double q) {
    totalAmount += amt;
    totalQty += q;
  }
}
