import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show ScrollNotification;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/auth_failure_policy.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../errors/user_facing_errors.dart';
import '../json_coerce.dart';
import '../navigation/surface_refresh_policy.dart' show kStockListCacheTtl;
import '../../features/shell/shell_branch_provider.dart';
import 'api_read_snapshots.dart';
import '../../features/stock/stock_list_row_patch.dart'
    show
        kStockListPatchAtKey,
        serverRowNewerThanPatch,
        stockListPatchFromStockDetail;
import 'app_period_provider.dart';
import 'deferred_invalidation.dart';
import 'home_dashboard_provider.dart';
import 'stock_list_exceptions.dart';

/// Public alias for providers outside this file (e.g. warehouse alerts).
void providerKeepAlive(Ref ref, Duration ttl) =>
    registerProviderKeepAliveTimer(ref, ttl);

final Map<String, Future<Map<String, dynamic>>> _stockListInflight = {};
final Map<String, Future<Map<String, dynamic>>> _openingMissingInflight = {};
final Map<String, Future<Map<String, dynamic>>> _deliveryCountsInflight = {};
final Map<String, Future<Map<String, dynamic>>> _stockAlertsSummaryInflight = {};

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

  /// Stable cache/dedupe key for list fetches (all query params except supplier).
  String toCacheKey() =>
      '$page|$perPage|$q|$category|$subcategory|'
      '$status|$sort|$includePeriod|$periodStart|$periodEnd|$purchasedInPeriod';

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

/// Home out-of-stock strip — small scoped list (not the stock page query).
const kHomeOutOfStockListQuery = StockListQuery(
  status: 'out',
  perPage: 8,
  page: 1,
  sort: 'stock_asc',
);

final homeOutOfStockListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'total': 0};
  }
  final result = await ref.read(hexaApiProvider).listStock(
        businessId: session.primaryBusiness.id,
        page: kHomeOutOfStockListQuery.page,
        perPage: kHomeOutOfStockListQuery.perPage,
        status: kHomeOutOfStockListQuery.status,
        sort: kHomeOutOfStockListQuery.sort,
      );
  if (providerWasDisposed(disposed)) {
    return {'items': <Map<String, dynamic>>[], 'total': 0};
  }
  return result;
});

/// Item drill-down: period purchases, variance, recent lines.
final stockItemIntelligenceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    throw const StockListFetchBlockedException('api_gate');
  }
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  final range = ref.watch(stockListQueryProvider);
  final result = await ref.read(hexaApiProvider).getStockIntelligence(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        periodStart: range.periodStart,
        periodEnd: range.periodEnd,
      );
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return result;
});

final stockItemActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    throw const StockListFetchBlockedException('api_gate');
  }
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  final result = await ref.read(hexaApiProvider).getStockItemActivity(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return result;
});

final stockListQueryProvider =
    StateProvider<StockListQuery>((_) => const StockListQuery());

/// Last successful `/stock/list` ETag + body (page 1, current query fingerprint).
final stockListEtagProvider = StateProvider<String?>((ref) => null);
final stockListCachedBodyProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
final stockListCacheQueryKeyProvider = StateProvider<String?>((ref) => null);

/// Last successful stock list fetch (page 1 ETag path) — gates shell tab refresh.
final stockListLastFetchedAtProvider = StateProvider<DateTime?>((ref) => null);

void clearStockListEtagCache(dynamic ref) {
  ref.read(stockListEtagProvider.notifier).state = null;
  ref.read(stockListCachedBodyProvider.notifier).state = null;
  ref.read(stockListCacheQueryKeyProvider.notifier).state = null;
  ref.read(stockListLastFetchedAtProvider.notifier).state = null;
}

/// Stock list period chips (Today / Week / Month / Year).
final stockPagePeriodProvider =
    StateProvider<HomePeriod>((_) => HomePeriod.allTime);

/// Tablet/desktop split pane selection.
final stockSelectedItemIdProvider = StateProvider<String?>((ref) => null);

/// Restored scroll position when returning to the stock list tab.
final stockListScrollOffsetProvider = StateProvider<double>((ref) => 0);

enum StockDeliveryFilter { all, pending, delivered }

/// Client-side delivery truck filter on stock list.
final stockDeliveryFilterProvider =
    StateProvider<StockDeliveryFilter>((ref) => StockDeliveryFilter.all);

/// True when list query narrows beyond default warehouse scope (search, period, etc.).
bool stockListHasScopedFilters(StockListQuery q, StockOperationalFilters op) {
  if (q.q.trim().isNotEmpty) return true;
  if (q.category.trim().isNotEmpty) return true;
  if (q.supplier.trim().isNotEmpty) return true;
  if (q.purchasedInPeriod) return true;
  if (op.evictionOnly) return true;
  if (op.purchasedInPeriodOnly) return true;
  return false;
}

/// RAM ETag cache must not replay an empty page-1 payload (dispose/auth race artifact).
bool stockListCacheBodyIsUsable(Map<String, dynamic>? body) {
  if (body == null || body.isEmpty) return false;
  if (body['_not_modified'] == true) return false;
  final total = coerceToInt(body['total']);
  if (total > 0) return true;
  final items = body['items'];
  return items is List && items.isNotEmpty;
}

/// Last successful page-1 body for the active query (survives autoDispose races on web).
Map<String, dynamic>? stockListCachedDataForCurrentQuery(dynamic ref) {
  final queryKey = ref.read(stockListQueryProvider).toCacheKey();
  final cacheKey = ref.read(stockListCacheQueryKeyProvider);
  if (cacheKey != queryKey) return null;
  final cached = ref.read(stockListCachedBodyProvider);
  if (!stockListCacheBodyIsUsable(cached)) return null;
  return Map<String, dynamic>.from(cached!);
}

void _writeStockListRamCache(
  dynamic ref, {
  required Map<String, dynamic> next,
  required StockListQuery query,
  required String queryKey,
  required Map<String, dynamic> res,
}) {
  try {
    final newEtag = res['_etag']?.toString();
    if (query.page == 1 && stockListCacheBodyIsUsable(next)) {
      if (newEtag != null && newEtag.isNotEmpty) {
        ref.read(stockListEtagProvider.notifier).state = newEtag;
      }
      ref.read(stockListCachedBodyProvider.notifier).state = next;
      ref.read(stockListCacheQueryKeyProvider.notifier).state = queryKey;
      ref.read(stockListLastFetchedAtProvider.notifier).state = DateTime.now();
    } else if (query.page == 1 && res['_not_modified'] != true) {
      ref.read(stockListLastFetchedAtProvider.notifier).state = DateTime.now();
    }
  } catch (_) {
    // Provider/container disposed — cache write is best-effort for the next mount.
  }
}

int _warehouseChipFilterCount(StockListQuery q, StockOperationalFilters op) {
  var n = 0;
  if (q.subcategory.isNotEmpty) n++;
  if (q.status != 'all') n++;
  if (op.missingBarcodeOnly) n++;
  if (op.missingItemCodeOnly) n++;
  if (op.reorderOnly) n++;
  if (op.unit.isNotEmpty) n++;
  return n;
}

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
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 3));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final totals = await ref.read(hexaApiProvider).getStockTotals(
        businessId: session.primaryBusiness.id,
      );
  if (providerWasDisposed(disposed)) return {};
  return totals;
});

/// Purchased qty totals for [period] (used when comparing to on-hand).
final stockTotalsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, AppPeriod>(
  (ref, period) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(minutes: 3));
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    final totals = await ref.read(hexaApiProvider).getStockTotals(
          businessId: session.primaryBusiness.id,
          periodStart: appPeriodApiDateFrom(ref, period),
          periodEnd: appPeriodApiDateTo(ref, period),
        );
    if (providerWasDisposed(disposed)) return {};
    return totals;
  },
);

/// Stock audit events for the stock page **Changes** tab (newest first).
/// Reads [stockAuditRecentSnapshotProvider] — no extra HTTP when home already loaded audit.
final stockChangesFeedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  ref.watch(stockPagePeriodProvider);
  final rows = await ref.watch(stockAuditRecentSnapshotProvider.future);
  if (providerWasDisposed(disposed)) return [];
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

Map<String, dynamic> _stockListFinalizePayload(
  Map<String, dynamic> res,
  dynamic ref, {
  required StockListQuery query,
  required String queryKey,
  required ProviderDisposeGuard disposed,
}) {
  final next = Map<String, dynamic>.from(res)..remove('_etag');
  _writeStockListRamCache(
    ref,
    next: next,
    query: query,
    queryKey: queryKey,
    res: res,
  );
  return next;
}

/// Kept alive (not autoDispose) — web IndexedStack + dispose races caused 200 + skeleton forever.
final stockListProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final keepAliveLink = ref.keepAlive();
  final keepAliveTimer = Timer(kStockListCacheTtl, keepAliveLink.close);
  ref.onDispose(keepAliveTimer.cancel);
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  await awaitProviderApiReady(ref);
  final skipApi = providerSkipApi(ref);
  if (skipApi) {
    final cachedBody = ref.read(stockListCachedBodyProvider);
    if (stockListCacheBodyIsUsable(cachedBody)) {
      return Map<String, dynamic>.from(cachedBody!);
    }
    final canForceLiveOnWeb = kIsWeb &&
        !ref.read(auth401CircuitOpenProvider) &&
        !ref.read(authSessionExpiredProvider);
    if (!canForceLiveOnWeb) {
      throw const StockListFetchBlockedException('api_gate');
    }
    // Web shell tabs: resume/refresh gates can stick while APIs are healthy (200).
  }
  final queryKey = query.toCacheKey();
  final cachedKey = ref.read(stockListCacheQueryKeyProvider);
  final cachedBody = ref.read(stockListCachedBodyProvider);
  final etag = ref.read(stockListEtagProvider);
  // Web service workers + IndexedStack dispose races make 304+ETag unreliable.
  final useEtag =
      !kIsWeb && query.page == 1 && cachedKey == queryKey && etag != null;
  final bid = session.primaryBusiness.id;
  final purchasedInPeriod = query.purchasedInPeriod ||
      ref.read(stockOperationalFiltersProvider).purchasedInPeriodOnly;
  final inflightKey =
      '$bid|$queryKey|${useEtag ? etag : ''}|$purchasedInPeriod';
  final api = ref.read(hexaApiProvider);

  Map<String, dynamic> res;
  try {
    res = await _stockListInflight.putIfAbsent(
      inflightKey,
      () => api
          .listStock(
            businessId: bid,
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
            purchasedInPeriod: purchasedInPeriod,
            ifNoneMatch: useEtag ? etag : null,
          )
          .whenComplete(() => _stockListInflight.remove(inflightKey)),
    );
  } on DioException {
    if (providerWasDisposed(disposed)) {
      if (stockListCacheBodyIsUsable(cachedBody)) {
        return Map<String, dynamic>.from(cachedBody!);
      }
      throw const ProviderFetchAborted();
    }
    rethrow;
  }

  if (res['_not_modified'] == true) {
    if (stockListCacheBodyIsUsable(cachedBody)) {
      return Map<String, dynamic>.from(cachedBody!);
    }
    // ETag matched but RAM cache missing (dispose/race) — bust and pull once.
    clearStockListEtagCache(ref);
    res = await api.listStock(
      businessId: bid,
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
      purchasedInPeriod: purchasedInPeriod,
    );
    if (res['_not_modified'] == true) {
      clearStockListEtagCache(ref);
      throw const StockListFetchBlockedException('etag_stale');
    }
  }

  // Web IndexedStack + autoDispose: fetch often completes after dispose guard trips.
  // Returning the payload prevents "Network 200 + skeleton forever" when XHR succeeded.
  return _stockListFinalizePayload(
    res,
    ref,
    query: query,
    queryKey: queryKey,
    disposed: disposed,
  );
});

/// Loads **all** stock rows matching [stockListQueryProvider] filters (paged API calls).
/// Used by bulk barcode print so the list is not limited to the stock screen page size.
/// Selected catalog item ids for bulk barcode PDF (stable across list rebuilds).
final bulkBarcodeSelectionProvider = StateProvider<Set<String>>((ref) => {});

/// Item ids successfully downloaded/printed this session (bulk barcode page).
final bulkBarcodeDownloadedIdsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Web lazy pagination cap for [bulkStockListProvider] (mobile loads up to 40 pages).
final bulkStockListMaxPageProvider = StateProvider<int>(
  (ref) => kIsWeb ? 1 : 40,
);

/// Request the next bulk stock list page (no-op when already at cap).
void requestBulkStockListNextPage(dynamic ref) {
  final cur = ref.read(bulkStockListMaxPageProvider);
  if (cur >= 40) return;
  ref.read(bulkStockListMaxPageProvider.notifier).state = cur + 1;
}

/// Lazy-load more bulk stock rows when the user scrolls near the list bottom.
bool handleBulkStockListScrollNotification(
  ScrollNotification notification,
  dynamic ref,
  Map<String, dynamic>? blob,
) {
  if (blob?['hasMore'] != true) return false;
  if (blob?['fetchFailed'] == true) return false;
  if (notification.metrics.pixels <
      notification.metrics.maxScrollExtent - 300) {
    return false;
  }
  requestBulkStockListNextPage(ref);
  return false;
}

final bulkStockListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
  final maxPages = ref.watch(bulkStockListMaxPageProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'total': 0, 'loaded': 0};
  }
  final api = ref.read(hexaApiProvider);
  // Smaller pages on web: large JSON over HTTP/3 (QUIC) often trips
  // ERR_QUIC_PROTOCOL_ERROR on flaky networks / Render cold paths.
  final pageSize = kIsWeb ? 50 : 500;
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  var total = 0;
  while (page <= maxPages) {
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
      if (providerWasDisposed(disposed)) {
        return {
          'items': merged,
          'total': total > 0 ? total : merged.length,
          'loaded': merged.length,
          'hasMore': total > merged.length,
        };
      }
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
          'hasMore': total > merged.length,
          'fetchFailed': true,
        };
      }
      rethrow;
    }
  }
  final hasMore = total > merged.length;
  return {
    'items': merged,
    'total': total,
    'loaded': merged.length,
    if (hasMore) 'hasMore': true,
  };
});

/// Optimistic list-row overlays until the next `/stock/list` fetch replaces them.
final stockListRowPatchProvider =
    StateProvider<Map<String, Map<String, dynamic>>>((ref) => const {});

/// Optimistic item-detail stock overlays (instant UI after save; cleared on refetch).
final stockItemDetailPatchProvider =
    StateProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, itemId) => const {},
);

void clearStockItemDetailPatch(dynamic ref, {required String itemId}) {
  if (itemId.isEmpty) return;
  ref.read(stockItemDetailPatchProvider(itemId).notifier).state = const {};
}

void applyStockItemDetailPatch(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> patch,
}) {
  if (itemId.isEmpty || patch.isEmpty) return;
  ref.read(stockItemDetailPatchProvider(itemId).notifier).update(
        (current) => {...current, ...patch},
      );
  final listPatch = stockListPatchFromStockDetail(patch);
  if (listPatch.isNotEmpty) {
    applyStockListRowPatch(ref, itemId: itemId, patch: listPatch);
  }
}

/// Apply save response instantly; reconcile with server in the background.
void applyStockItemDetailFromSave(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> saved,
}) {
  if (itemId.isEmpty || saved.isEmpty) return;
  applyStockItemDetailPatch(ref, itemId: itemId, patch: saved);
  deferInvalidateDelayed(ref, stockItemDetailProvider(itemId));
}

void applyStockListRowPatch(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> patch,
}) {
  if (itemId.isEmpty || patch.isEmpty) return;
  final tagged = {
    ...patch,
    kStockListPatchAtKey: DateTime.now().toUtc().toIso8601String(),
  };
  ref.read(stockListRowPatchProvider.notifier).update((current) {
    return {
      ...current,
      itemId: {...?current[itemId], ...tagged},
    };
  });
  if (kDebugMode) {
    debugPrint(
      '[STOCK_UI_REFRESH] itemId=$itemId patchKeys=${patch.keys.toList()}',
    );
  }
}

/// Drop optimistic patches once `/stock/list` returns fresher server rows.
void reconcileStockListRowPatches(
  dynamic ref,
  Iterable<Map<String, dynamic>> serverRows,
) {
  final patches = ref.read(stockListRowPatchProvider);
  if (patches.isEmpty) return;
  final staleIds = <String>[];
  for (final row in serverRows) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) continue;
    final patch = patches[id];
    if (patch == null) continue;
    if (serverRowNewerThanPatch(row, patch)) staleIds.add(id);
  }
  if (staleIds.isNotEmpty) {
    clearStockListRowPatchesForIds(ref, staleIds);
  }
}

void clearStockListRowPatchesForIds(
  dynamic ref,
  Iterable<String> itemIds,
) {
  final ids = itemIds.where((id) => id.isNotEmpty).toSet();
  if (ids.isEmpty) return;
  ref.read(stockListRowPatchProvider.notifier).update((current) {
    final next = Map<String, Map<String, dynamic>>.from(current);
    for (final id in ids) {
      next.remove(id);
    }
    return next;
  });
}

/// Realtime single-item refresh: fetch one row and patch list cache (no full list refetch).
Future<void> patchStockItemInCache(
  dynamic ref, {
  required String itemId,
}) async {
  if (itemId.isEmpty) return;
  final session = ref.read(sessionProvider);
  if (session == null) return;
  try {
    final detail = await ref.read(hexaApiProvider).getStockItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
        );
    final patch = stockListPatchFromStockDetail(detail);
    if (patch.isNotEmpty) {
      applyStockListRowPatch(ref, itemId: itemId, patch: patch);
    }
    clearStockItemDetailPatch(ref, itemId: itemId);
    ref.invalidate(stockItemDetailProvider(itemId));
    ref.invalidate(stockItemIntelligenceProvider(itemId));
    ref.invalidate(stockItemActivityProvider(itemId));
  } catch (e, st) {
    logSilencedApiError(e, st);
    ref.invalidate(stockItemDetailProvider(itemId));
    ref.invalidate(stockItemActivityProvider(itemId));
  }
}

/// Stock row + recent purchases for catalog item detail / sheets.
final stockItemDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, itemId) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
    final session = ref.watch(sessionProvider);
    if (session == null) {
      throw const StockListFetchBlockedException('no_session');
    }
    await awaitProviderApiReady(ref);
    if (providerSkipApi(ref)) {
      throw const StockListFetchBlockedException('api_gate');
    }
    if (providerWasDisposed(disposed)) {
      throw const ProviderFetchAborted();
    }
    try {
      final row = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      if (providerWasDisposed(disposed)) {
        throw const ProviderFetchAborted();
      }
      clearStockItemDetailPatch(ref, itemId: itemId);
      return normalizeStockDetailMap(row);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {};
      if (providerWasDisposed(disposed)) {
        throw const ProviderFetchAborted();
      }
      rethrow;
    }
  },
);

final stockItemAuditProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, itemId) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    final rows = await ref.read(hexaApiProvider).listStockAuditForItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
        );
    if (providerWasDisposed(disposed)) return [];
    return rows;
  },
);

/// Raw GET `/stock/alerts/summary` — SSOT for chip counts off Home bundle.
final stockAlertsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 30));
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) return const {};
  final bid = session.primaryBusiness.id;
  final summary = await _stockAlertsSummaryInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .getStockAlertsSummary(businessId: bid)
        .whenComplete(() => _stockAlertsSummaryInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) return const {};
  return summary;
});

Map<String, int> _stockStatusCountsFromAlertsSummary(
  Map<String, dynamic> summary, {
  int? allTotal,
}) {
  final outCount = (summary['active_out_of_stock'] as num?)?.toInt() ??
      (summary['out_of_stock'] as num?)?.toInt() ??
      0;
  final resolvedAll = allTotal ??
      (summary['total_items'] as num?)?.toInt();
  return {
    'all': resolvedAll ?? 0,
    'low': (summary['low_stock'] as num?)?.toInt() ?? 0,
    'critical': (summary['critical_stock'] as num?)?.toInt() ?? 0,
    'out': outCount,
    'missing_code': (summary['missing_item_code'] as num?)?.toInt() ?? 0,
    'missing_barcode': (summary['missing_barcode'] as num?)?.toInt() ?? 0,
  };
}

/// Status bucket counts for stock filter chips (authoritative server summary).
final stockStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final bundled = homeBundledStockStatusCounts(ref);
  if (bundled != null) return bundled;
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  final summary = await ref.watch(stockAlertsSummaryProvider.future);
  if (providerWasDisposed(disposed)) return {};
  final allTotal = (summary['total_items'] as num?)?.toInt();
  if (allTotal != null && allTotal > 0) {
    return _stockStatusCountsFromAlertsSummary(summary, allTotal: allTotal);
  }

  final res = await api.listStock(
    businessId: bid,
    page: 1,
    perPage: 1,
    status: 'all',
    sort: 'recent',
  );
  if (providerWasDisposed(disposed)) return {};
  return _stockStatusCountsFromAlertsSummary(
    summary,
    allTotal: (res['total'] as num?)?.toInt() ?? 0,
  );
});

/// Pending/delivered truck counts for stock list filter chips.
final stockDeliveryIndicatorCountsProvider = FutureProvider.autoDispose<
    ({int pending, int delivered})>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 25));
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) {
    return (pending: 0, delivered: 0);
  }
  final query = ref.watch(stockListQueryProvider);
  final op = ref.watch(stockOperationalFiltersProvider);
  final bid = session.primaryBusiness.id;
  final inflightKey =
      '$bid|${query.toCacheKey()}|${op.missingBarcodeOnly}|${op.missingItemCodeOnly}|'
      '${op.reorderOnly}|${op.unit}';
  final api = ref.read(hexaApiProvider);
  final counts = await _deliveryCountsInflight.putIfAbsent(
    inflightKey,
    () => api
        .stockDeliveryIndicatorCounts(
          businessId: bid,
          q: query.q,
          category: query.category,
          subcategory: query.subcategory,
          status: query.status,
          sort: query.sort,
          includePeriod: query.includePeriod,
          periodStart: query.periodStart,
          periodEnd: query.periodEnd,
          missingBarcode: op.missingBarcodeOnly,
          missingItemCode: op.missingItemCodeOnly,
          reorderOnly: op.reorderOnly,
          unit: op.unit,
        )
        .whenComplete(() => _deliveryCountsInflight.remove(inflightKey)),
  );
  if (providerWasDisposed(disposed)) return (pending: 0, delivered: 0);
  return (
    pending: coerceToInt(counts['pending']),
    delivered: coerceToInt(counts['delivered']),
  );
});

/// All/Low/Out chip counts — scoped when warehouse filters are active.
final stockFilteredStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 25));
  final q = ref.watch(stockListQueryProvider);
  final op = ref.watch(stockOperationalFiltersProvider);
  if (_warehouseChipFilterCount(q, op) == 0 &&
      !stockListHasScopedFilters(q, op)) {
    return ref.watch(stockStatusCountsProvider.future);
  }
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  Future<int> totalFor(String status) async {
    final res = await api.listStock(
      businessId: bid,
      page: 1,
      perPage: 1,
      q: q.q,
      category: q.category,
      subcategory: q.subcategory,
      status: status,
      sort: q.sort,
      includePeriod: q.includePeriod,
      periodStart: q.periodStart,
      periodEnd: q.periodEnd,
      purchasedInPeriod: q.purchasedInPeriod || op.purchasedInPeriodOnly,
      missingBarcode: op.missingBarcodeOnly,
      missingItemCode: op.missingItemCodeOnly,
      reorderOnly: op.reorderOnly,
      unit: op.unit,
    );
    return (res['total'] as num?)?.toInt() ?? 0;
  }

  final low = await totalFor('low');
  if (providerWasDisposed(disposed)) return {};
  final critical = await totalFor('critical');
  if (providerWasDisposed(disposed)) return {};
  return {
    'all': await totalFor('all'),
    'low': low,
    'critical': critical,
    'out': await totalFor('out'),
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
      perPage: 50,
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
  final mounted = ref.watch(lowStockDashboardMountedProvider);
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      mounted < 1 &&
      !ref.watch(homeLowStockDetailFetchEnabledProvider)) {
    return {};
  }
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final lowRows = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final st in ['low', 'critical', 'out']) {
    final chunk = await _fetchStockListAllPages(
      api: api,
      businessId: bid,
      status: st,
      maxPages: 20,
    );
    if (providerWasDisposed(disposed)) return {};
    for (final item in chunk) {
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) {
        if (seen.add(id)) lowRows.add(item);
      } else {
        lowRows.add(item);
      }
    }
  }
  if (providerWasDisposed(disposed)) {
    return {};
  }
  final byId = <String, Map<String, dynamic>>{};
  for (final item in lowRows) {
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
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
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
    final body = await ref.read(hexaApiProvider).listOpeningStockSetup(
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
    if (providerWasDisposed(disposed)) {
      return {
        'summary': {},
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': query.page,
        'per_page': query.perPage,
      };
    }
    return body;
  },
);

/// Bulk selection state for the Opening Stock Setup page.
final openingStockBulkSelectionProvider = StateProvider<Set<String>>(
  (ref) => {},
);

/// Items missing opening stock (home banners + critical alerts).
final openingStockMissingProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (!homeOverviewReadyForSatellites(ref)) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  final bid = session.primaryBusiness.id;
  final body = await _openingMissingInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .getMissingOpeningStock(businessId: bid)
        .whenComplete(() => _openingMissingInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) {
    return {'items': <Map<String, dynamic>>[], 'missing_count': 0};
  }
  return body;
});
