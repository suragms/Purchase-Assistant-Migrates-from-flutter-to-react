import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

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
    this.sort = 'name',
    this.includePeriod = false,
    this.periodStart,
    this.periodEnd,
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

final stockTotalsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getStockTotals(
        businessId: session.primaryBusiness.id,
      );
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
  const pageSize = 500;
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  var total = 0;
  while (page <= 40) {
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
