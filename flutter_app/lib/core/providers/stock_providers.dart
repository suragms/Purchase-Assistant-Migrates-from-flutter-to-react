import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import 'app_period_provider.dart';
import 'home_dashboard_provider.dart';

void providerKeepAlive(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  final timer = Timer(ttl, link.close);
  ref.onDispose(timer.cancel);
}

/// Query for GET `/v1/businesses/{id}/stock/list`.
class StockListQuery {
  const StockListQuery({
    this.page = 1,
    this.perPage = 50,
    this.q = '',
    this.category = '',
    this.subcategory = '',
    this.supplier = '',
    this.status = 'all',
    this.sort = 'recent',
    this.includePeriod = false,
    this.periodStart,
    this.periodEnd,
    this.purchasedInPeriod = false,
  });

  final int page;
  final int perPage;
  final String q;
  final String category;
  final String subcategory;

  /// Client-side filter on `supplier_name` in list rows (API has no supplier param).
  final String supplier;

  /// `all` | `healthy` | `low` | `critical` | `out`
  final String status;

  /// `name` | `stock_asc` | `stock_desc` | `recent`
  final String sort;

  final bool includePeriod;
  final String? periodStart;
  final String? periodEnd;

  /// Server-side: only items with period purchases (requires [includePeriod]).
  final bool purchasedInPeriod;

  StockListQuery copyWith({
    int? page,
    int? perPage,
    String? q,
    String? category,
    String? subcategory,
    String? supplier,
    String? status,
    String? sort,
    bool? includePeriod,
    String? periodStart,
    String? periodEnd,
    bool? purchasedInPeriod,
  }) {
    return StockListQuery(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      q: q ?? this.q,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      supplier: supplier ?? this.supplier,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      includePeriod: includePeriod ?? this.includePeriod,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      purchasedInPeriod: purchasedInPeriod ?? this.purchasedInPeriod,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockListQuery &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          perPage == other.perPage &&
          q == other.q &&
          category == other.category &&
          subcategory == other.subcategory &&
          supplier == other.supplier &&
          status == other.status &&
          sort == other.sort &&
          includePeriod == other.includePeriod &&
          periodStart == other.periodStart &&
          periodEnd == other.periodEnd &&
          purchasedInPeriod == other.purchasedInPeriod;

  @override
  int get hashCode => Object.hash(
        page,
        perPage,
        q,
        category,
        subcategory,
        supplier,
        status,
        sort,
        includePeriod,
        periodStart,
        periodEnd,
        purchasedInPeriod,
      );
}

/// Home out-of-stock strip — small scoped list (not the stock page query).
const kHomeOutOfStockListQuery = StockListQuery(
  status: 'out',
  perPage: 8,
  page: 1,
  sort: 'stock_asc',
);

/// Item drill-down: period purchases, variance, recent lines.
final stockItemIntelligenceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final range = ref.watch(stockListQueryProvider);
  return ref.read(hexaApiProvider).getStockIntelligence(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        periodStart: range.periodStart,
        periodEnd: range.periodEnd,
      );
});

final stockItemActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getStockItemActivity(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
});

final stockListQueryProvider =
    StateProvider<StockListQuery>((_) => const StockListQuery());

/// Stock list period chips (Today / Week / Month / Year).
final stockPagePeriodProvider =
    StateProvider<HomePeriod>((_) => HomePeriod.allTime);

/// Tablet/desktop split pane selection.
final stockSelectedItemIdProvider = StateProvider<String?>((ref) => null);

enum StockDeliveryFilter { all, pending, delivered }

/// Client-side delivery truck filter on stock list.
final stockDeliveryFilterProvider =
    StateProvider<StockDeliveryFilter>((ref) => StockDeliveryFilter.all);

/// Client-side filters shared by stock + bulk print.
class StockOperationalFilters {
  const StockOperationalFilters({
    this.missingBarcodeOnly = false,
    this.missingItemCodeOnly = false,
    this.reorderOnly = false,
    this.evictionOnly = false,
    this.purchasedInPeriodOnly = false,
    this.unit = '',
  });

  final bool missingBarcodeOnly;
  final bool missingItemCodeOnly;
  final bool reorderOnly;
  final bool evictionOnly;
  final bool purchasedInPeriodOnly;

  /// Empty = all units; else match `unit` field lowercased.
  final String unit;

  StockOperationalFilters copyWith({
    bool? missingBarcodeOnly,
    bool? missingItemCodeOnly,
    bool? reorderOnly,
    bool? evictionOnly,
    bool? purchasedInPeriodOnly,
    String? unit,
    bool clearUnit = false,
    bool clearMissingItemCode = false,
    bool clearEviction = false,
  }) {
    return StockOperationalFilters(
      missingBarcodeOnly: missingBarcodeOnly ?? this.missingBarcodeOnly,
      missingItemCodeOnly: clearMissingItemCode
          ? false
          : (missingItemCodeOnly ?? this.missingItemCodeOnly),
      reorderOnly: reorderOnly ?? this.reorderOnly,
      evictionOnly: clearEviction ? false : (evictionOnly ?? this.evictionOnly),
      purchasedInPeriodOnly:
          purchasedInPeriodOnly ?? this.purchasedInPeriodOnly,
      unit: clearUnit ? '' : (unit ?? this.unit),
    );
  }
}

final stockOperationalFiltersProvider = StateProvider<StockOperationalFilters>(
    (_) => const StockOperationalFilters());

/// Selected row for bulk print desktop preview panel.
final bulkPreviewItemIdProvider = StateProvider<String?>((ref) => null);

int countOperationalActiveFilters(
    StockListQuery q, StockOperationalFilters op) {
  var n = 0;
  if (q.category.isNotEmpty) n++;
  if (q.subcategory.isNotEmpty) n++;
  if (q.supplier.isNotEmpty) n++;
  if (q.status != 'all') n++;
  if (q.sort != 'recent') n++;
  if (op.missingBarcodeOnly) n++;
  if (op.missingItemCodeOnly) n++;
  if (op.reorderOnly) n++;
  if (op.evictionOnly) n++;
  if (op.purchasedInPeriodOnly) n++;
  if (op.unit.isNotEmpty) n++;
  return n;
}

/// On-hand warehouse totals (bags/kg/boxes/tins). Never pass period — that returns purchases.
final stockOnHandTotalsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  providerKeepAlive(ref, const Duration(minutes: 3));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getStockTotals(
        businessId: session.primaryBusiness.id,
      );
});

/// Purchased qty totals for [period] (used when comparing to on-hand).
final stockTotalsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, AppPeriod>(
  (ref, period) async {
    providerKeepAlive(ref, const Duration(minutes: 3));
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).getStockTotals(
          businessId: session.primaryBusiness.id,
          periodStart: appPeriodApiDateFrom(ref, period),
          periodEnd: appPeriodApiDateTo(ref, period),
        );
  },
);

/// Stock audit events for the stock page **Changes** tab (newest first).
final stockChangesFeedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  providerKeepAlive(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  ref.watch(stockPagePeriodProvider);
  final rows = await ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: HexaApi.stockAuditRecentMaxLimit,
      );
  final period = ref.read(stockPagePeriodProvider);
  final range = homePeriodRange(period, now: DateTime.now());
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(
    range.end.year,
    range.end.month,
    range.end.day,
    23,
    59,
    59,
  );
  final out = <Map<String, dynamic>>[];
  for (final raw in rows) {
    final m = Map<String, dynamic>.from(raw);
    final at = DateTime.tryParse(
          m['created_at']?.toString() ?? m['audited_at']?.toString() ?? '',
        ) ??
        DateTime.tryParse(m['on']?.toString() ?? '');
    if (at == null) continue;
    if (at.isBefore(from) || at.isAfter(end)) continue;
    out.add(m);
  }
  out.sort((a, b) {
    final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });
  return out;
});

/// Shared GET `/stock/list` cache — dedupes home + stock page watchers (30s TTL).
final stockListCacheProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, StockListQuery>((ref, query) async {
  providerKeepAlive(ref, const Duration(seconds: 30));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return <String, dynamic>{
      'items': <dynamic>[],
      'total': 0,
      'page': 1,
      'per_page': query.perPage,
    };
  }
  return ref.read(hexaApiProvider).listStock(
        businessId: session.primaryBusiness.id,
        page: query.page,
        perPage: query.perPage,
        q: query.q,
        category: query.category,
        subcategory: query.subcategory,
        status: query.status,
        sort: query.sort,
        includePeriod: query.includePeriod,
        periodStart: query.periodStart,
        periodEnd: query.periodEnd,
        purchasedInPeriod: query.purchasedInPeriod,
      );
});

/// Stock page list — reads [stockListCacheProvider] for the active [stockListQueryProvider].
final stockListProvider = FutureProvider.autoDispose((ref) async {
  final query = ref.watch(stockListQueryProvider);
  final purchasedInPeriod = query.purchasedInPeriod ||
      ref.read(stockOperationalFiltersProvider).purchasedInPeriodOnly;
  final effective = purchasedInPeriod == query.purchasedInPeriod
      ? query
      : query.copyWith(purchasedInPeriod: purchasedInPeriod);
  return ref.watch(stockListCacheProvider(effective).future);
});

/// Loads **all** stock rows matching [stockListQueryProvider] filters (paged API calls).
/// Used by bulk barcode print so the list is not limited to the stock screen page size.
/// Selected catalog item ids for bulk barcode PDF (stable across list rebuilds).
final bulkBarcodeSelectionProvider = StateProvider<Set<String>>((ref) => {});

/// Item ids successfully downloaded/printed this session (bulk barcode page).
final bulkBarcodeDownloadedIdsProvider =
    StateProvider<Set<String>>((ref) => {});

final bulkStockListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'total': 0, 'loaded': 0};
  }
  final api = ref.read(hexaApiProvider);
  // Smaller pages on web: large JSON over HTTP/3 (QUIC) often trips
  // ERR_QUIC_PROTOCOL_ERROR on flaky networks / Render cold paths.
  final pageSize = kIsWeb ? 100 : 500;
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  var total = 0;
  while (page <= 40) {
    try {
      final res = await api.listStock(
        businessId: session.primaryBusiness.id,
        page: page,
        perPage: pageSize,
        q: query.q,
        category: query.category,
        subcategory: query.subcategory,
        status: query.status,
        sort: query.sort,
        includePeriod: query.includePeriod,
        periodStart: query.periodStart,
        periodEnd: query.periodEnd,
      );
      total = (res['total'] as num?)?.toInt() ?? 0;
      final raw = (res['items'] as List?) ?? const [];
      if (raw.isEmpty) break;
      for (final e in raw) {
        if (e is Map) merged.add(Map<String, dynamic>.from(e));
      }
      if (merged.length >= total) break;
      page++;
    } on DioException {
      if (merged.isNotEmpty) {
        return {
          'items': merged,
          'total': total > 0 ? total : merged.length,
          'loaded': merged.length,
          'partial': true,
        };
      }
      rethrow;
    }
  }
  return {'items': merged, 'total': total, 'loaded': merged.length};
});

/// Stock row + recent purchases for catalog item detail / sheets.
final stockItemDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, itemId) async {
    final keepAlive = ref.keepAlive();
    final timer = Timer(const Duration(seconds: 30), keepAlive.close);
    ref.onDispose(timer.cancel);

    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    try {
      return await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {};
      rethrow;
    }
  },
);

final stockItemAuditProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, itemId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listStockAuditForItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
        );
  },
);

/// Status bucket counts for stock filter chips (authoritative server summary).
final stockStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), keepAlive.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  final summary = await api.getStockAlertsSummary(businessId: bid);
  final allTotal = (summary['total_items'] as num?)?.toInt();
  final outCount = (summary['active_out_of_stock'] as num?)?.toInt() ??
      (summary['out_of_stock'] as num?)?.toInt() ??
      0;
  if (allTotal != null && allTotal > 0) {
    return {
      'all': allTotal,
      'low': (summary['low_stock'] as num?)?.toInt() ?? 0,
      'critical': (summary['critical_stock'] as num?)?.toInt() ?? 0,
      'out': outCount,
      'missing_code': (summary['missing_item_code'] as num?)?.toInt() ?? 0,
      'missing_barcode': (summary['missing_barcode'] as num?)?.toInt() ?? 0,
    };
  }

  final res = await api.listStock(
    businessId: bid,
    page: 1,
    perPage: 1,
    status: 'all',
    sort: 'recent',
  );
  return {
    'all': (res['total'] as num?)?.toInt() ?? 0,
    'low': (summary['low_stock'] as num?)?.toInt() ?? 0,
    'critical': (summary['critical_stock'] as num?)?.toInt() ?? 0,
    'out': outCount,
    'missing_code': (summary['missing_item_code'] as num?)?.toInt() ?? 0,
    'missing_barcode': (summary['missing_barcode'] as num?)?.toInt() ?? 0,
  };
});

/// Low-stock items grouped category → subcategory → rows.
typedef LowStockByCategoryMap
    = Map<String, Map<String, List<Map<String, dynamic>>>>;

Future<List<Map<String, dynamic>>> _fetchStockListAllPages({
  required HexaApi api,
  required String businessId,
  required String status,
  int maxPages = 10,
  bool includePeriod = false,
  String? periodStart,
  String? periodEnd,
}) async {
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  while (page <= maxPages) {
    final res = await api.listStock(
      businessId: businessId,
      page: page,
      perPage: 200,
      status: status,
      sort: 'stock_asc',
      includePeriod: includePeriod,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final total = (res['total'] as num?)?.toInt() ?? 0;
    final raw = (res['items'] as List?) ?? const [];
    if (raw.isEmpty) break;
    for (final e in raw) {
      if (e is Map) merged.add(Map<String, dynamic>.from(e));
    }
    if (merged.length >= total) break;
    page++;
  }
  return merged;
}

final lowStockByCategoryProvider =
    FutureProvider.autoDispose<LowStockByCategoryMap>((ref) async {
  providerKeepAlive(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final period = ref.watch(homePeriodProvider);
  final customRange = ref.watch(analyticsDateRangeProvider);
  final range = homePeriodRange(
    period,
    now: DateTime.now(),
    custom: period == HomePeriod.custom
        ? (start: customRange.from, endInclusive: customRange.to)
        : null,
  );
  final periodStart =
      '${range.start.year}-${range.start.month.toString().padLeft(2, '0')}-${range.start.day.toString().padLeft(2, '0')}';
  final periodEnd =
      '${range.end.year}-${range.end.month.toString().padLeft(2, '0')}-${range.end.day.toString().padLeft(2, '0')}';
  final lowRows = await _fetchStockListAllPages(
    api: api,
    businessId: bid,
    status: 'all',
    includePeriod: true,
    periodStart: periodStart,
    periodEnd: periodEnd,
  );
  final byId = <String, Map<String, dynamic>>{};
  for (final item in lowRows) {
    final status = (item['stock_status']?.toString() ?? '').toLowerCase();
    final pendingDel =
        (item['pending_delivery_qty'] as num?)?.toDouble() ?? 0.0;
    final pendingDelivery = item['has_pending_order'] == true &&
        item['last_purchase_delivered'] == false;
    if (status != 'low' &&
        status != 'out' &&
        status != 'critical' &&
        pendingDel <= 0.001 &&
        !pendingDelivery) {
      continue;
    }
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      byId[id] = item;
    } else {
      byId['_${byId.length}'] = item;
    }
  }
  final merged = byId.values.toList();

  final result = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final item in merged) {
    final cat = item['category_name']?.toString().trim();
    final catKey = (cat != null && cat.isNotEmpty) ? cat : 'Unknown';
    final sub = item['subcategory_name']?.toString().trim();
    final subKey = (sub != null && sub.isNotEmpty) ? sub : 'Other';
    result.putIfAbsent(catKey, () => {});
    result[catKey]!.putIfAbsent(subKey, () => []);
    result[catKey]![subKey]!.add(item);
  }
  return result;
});

/// Query for `GET /v1/businesses/{id}/stock/opening/setup`.
class OpeningStockSetupQuery {
  const OpeningStockSetupQuery({
    this.page = 1,
    this.perPage = 50,
    this.q = '',
    this.status = 'all',
    this.stockStatus = 'all',
    this.missingBarcode = false,
    this.missingItemCode = false,
    this.category = '',
    this.subcategory = '',
    this.supplierId,
    this.unit = '',
    this.updatedToday = false,
    this.updatedBy = '',
  });

  final int page;
  final int perPage;
  final String q;

  /// `all` | `pending` | `completed`
  final String status;
  final String stockStatus;
  final bool missingBarcode;
  final bool missingItemCode;
  final String category;
  final String subcategory;
  final String? supplierId;
  final String unit;
  final bool updatedToday;
  final String updatedBy;

  OpeningStockSetupQuery copyWith({
    int? page,
    int? perPage,
    String? q,
    String? status,
    String? stockStatus,
    bool? missingBarcode,
    bool? missingItemCode,
    String? category,
    String? subcategory,
    String? supplierId,
    String? unit,
    bool? updatedToday,
    String? updatedBy,
  }) {
    return OpeningStockSetupQuery(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      q: q ?? this.q,
      status: status ?? this.status,
      stockStatus: stockStatus ?? this.stockStatus,
      missingBarcode: missingBarcode ?? this.missingBarcode,
      missingItemCode: missingItemCode ?? this.missingItemCode,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      supplierId: supplierId ?? this.supplierId,
      unit: unit ?? this.unit,
      updatedToday: updatedToday ?? this.updatedToday,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

final openingStockSetupQueryProvider =
    StateProvider<OpeningStockSetupQuery>(
      (_) => const OpeningStockSetupQuery(),
    );

/// Server-backed list: summary + rows.
final openingStockSetupProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    providerKeepAlive(ref, const Duration(minutes: 2));
    final session = ref.watch(sessionProvider);
    if (session == null) {
      return {
        'summary': {},
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'per_page': ref.read(openingStockSetupQueryProvider).perPage,
      };
    }
    final query = ref.watch(openingStockSetupQueryProvider);
    return ref.read(hexaApiProvider).listOpeningStockSetup(
      businessId: session.primaryBusiness.id,
      page: query.page,
      perPage: query.perPage,
      q: query.q,
      status: query.status,
      stockStatus: query.stockStatus,
      missingBarcode: query.missingBarcode,
      missingItemCode: query.missingItemCode,
      category: query.category,
      subcategory: query.subcategory,
      supplierId: query.supplierId,
      unit: query.unit,
      updatedToday: query.updatedToday,
      updatedBy: query.updatedBy,
    );
  },
);

/// Bulk selection state for the Opening Stock Setup page.
final openingStockBulkSelectionProvider = StateProvider<Set<String>>(
  (ref) => {},
);

/// Items missing opening stock (home banners + critical alerts).
final openingStockMissingProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  providerKeepAlive(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  return ref.read(hexaApiProvider).getMissingOpeningStock(
        businessId: session.primaryBusiness.id,
      );
});
