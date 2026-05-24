import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/session_notifier.dart';
import 'app_period_provider.dart';
import 'home_dashboard_provider.dart';

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
}

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

final stockListQueryProvider =
    StateProvider<StockListQuery>((_) => const StockListQuery());

/// Stock list period chips (Today / Week / Month / Year).
final stockPagePeriodProvider =
    StateProvider<HomePeriod>((_) => HomePeriod.allTime);

/// Tablet/desktop split pane selection.
final stockSelectedItemIdProvider = StateProvider<String?>((ref) => null);

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

final stockOperationalFiltersProvider =
    StateProvider<StockOperationalFilters>((_) => const StockOperationalFilters());

/// Selected row for bulk print desktop preview panel.
final bulkPreviewItemIdProvider = StateProvider<String?>((ref) => null);

int countOperationalActiveFilters(StockListQuery q, StockOperationalFilters op) {
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

final stockListProvider = FutureProvider.autoDispose((ref) async {
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
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
        purchasedInPeriod: query.purchasedInPeriod ||
            ref.read(stockOperationalFiltersProvider).purchasedInPeriodOnly,
      );
});

/// Loads **all** stock rows matching [stockListQueryProvider] filters (paged API calls).
/// Used by bulk barcode print so the list is not limited to the stock screen page size.
/// Selected catalog item ids for bulk barcode PDF (stable across list rebuilds).
final bulkBarcodeSelectionProvider = StateProvider<Set<String>>((ref) => {});

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
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  final summary = await api.getStockAlertsSummary(businessId: bid);
  final allTotal = (summary['total_items'] as num?)?.toInt();
  if (allTotal != null && allTotal > 0) {
    return {
      'all': allTotal,
      'low': (summary['low_stock'] as num?)?.toInt() ?? 0,
      'out': (summary['out_of_stock'] as num?)?.toInt() ?? 0,
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
    'out': (summary['out_of_stock'] as num?)?.toInt() ?? 0,
    'missing_code': (summary['missing_item_code'] as num?)?.toInt() ?? 0,
    'missing_barcode': (summary['missing_barcode'] as num?)?.toInt() ?? 0,
  };
});

/// Low-stock items grouped category → subcategory → rows.
typedef LowStockByCategoryMap =
    Map<String, Map<String, List<Map<String, dynamic>>>>;

final lowStockByCategoryProvider =
    FutureProvider.autoDispose<LowStockByCategoryMap>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  while (page <= 10) {
    final res = await api.listStock(
      businessId: bid,
      page: page,
      perPage: 200,
      status: 'low',
      sort: 'stock_asc',
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
