import 'dart:async';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart';
import 'home_owner_dashboard_providers.dart';
import 'analytics_breakdown_providers.dart';
import 'business_write_event.dart';
import 'business_write_revision.dart';
import 'item_detail_providers.dart';
import 'analytics_kpi_provider.dart';
import 'reports_provider.dart';
import 'reports_bi_providers.dart';
import 'brokers_list_provider.dart';
import 'catalog_providers.dart';
import 'contacts_hub_provider.dart';
import 'full_reports_insights_providers.dart';
import 'reports_prior_period_provider.dart';
import 'suppliers_list_provider.dart';
import 'trade_purchases_provider.dart';
import 'business_users_provider.dart';
import 'delivery_pipeline_provider.dart';
import 'low_stock_providers.dart';
import 'staff_home_providers.dart';
import 'stock_providers.dart';
import '../../features/purchase/providers/trade_purchase_detail_provider.dart';
import '../models/trade_purchase_models.dart';
import 'server_notifications_provider.dart';
import 'warehouse_alerts_provider.dart';

// Debounce guard: prevent stampede when called from multiple sources within 400ms.
Timer? _invalidateDebounce;
const _invalidateDebounceMs = 150;
DateTime? _lastDashboardInvalidateAt;
const _dashboardInvalidateMinGap = Duration(seconds: 5);

/// Immediate owner home refresh after writes (bypasses debounced aggregate gap).
void forceRefreshOwnerHomeDashboard(dynamic ref) {
  bustHomeDashboardVolatileCaches();
  bustHomeShellReportsInflight();
  _lastDashboardInvalidateAt = DateTime.now();
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(homeRecentActivityFeedProvider);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(homeStockAttentionCountProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(deliveryPipelineProvider);
}

/// KPIs and tables that depend on [analyticsDateRangeProvider] and/or entries.
/// [ref] is any Riverpod `Ref` / `WidgetRef` with `invalidate`.
void invalidateAnalyticsData(dynamic ref) {
  markReportsPurchasesNeedsLiveFetch(ref);
  ref.invalidate(analyticsKpiProvider);
  ref.invalidate(analyticsDailyProfitProvider);
  ref.invalidate(analyticsItemsTableProvider);
  ref.invalidate(analyticsCategoriesTableProvider);
  ref.invalidate(analyticsTypesTableProvider);
  ref.invalidate(analyticsSuppliersTableProvider);
  ref.invalidate(analyticsBrokersTableProvider);
  ref.invalidate(analyticsBestSupplierInsightProvider);
  ref.invalidate(fullReportsInsightsProvider);
  ref.invalidate(fullReportsGoalsProvider);
  ref.invalidate(reportsPriorPeriodDeltaProvider);
  ref.invalidate(reportsPurchasesPayloadProvider);
  ref.invalidate(reportsPeriodComparisonProvider);
  ref.invalidate(reportsMovementSummaryProvider);
}

/// After purchases, entries, or other business writes, bust derived KPIs so
/// Home, Reports, Contacts KPIs, and lists do not show stale numbers.
void invalidateBusinessAggregates(dynamic ref) {
  _invalidateDebounce?.cancel();
  _invalidateDebounce = Timer(
    const Duration(milliseconds: _invalidateDebounceMs),
    () {
      _invalidateDebounce = null;
      _doInvalidateBusinessAggregates(ref);
    },
  );
}

void _doInvalidateBusinessAggregates(dynamic ref) {
  bustHomeDashboardVolatileCaches();
  bustHomeShellReportsInflight();
  bustReportsPurchasesInflight();
  final session = ref.read(sessionProvider);
  if (session != null) {
    unawaited(
      OfflineStore.bustTradeAggregateCachesForBusiness(session.primaryBusiness.id),
    );
  }
  invalidateAnalyticsData(ref);
  final now = DateTime.now();
  final allowDashboardInvalidate = _lastDashboardInvalidateAt == null ||
      now.difference(_lastDashboardInvalidateAt!) >= _dashboardInvalidateMinGap;
  if (allowDashboardInvalidate) {
    _lastDashboardInvalidateAt = now;
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeShellReportsProvider);
  }
  ref.invalidate(homeInventorySummaryProvider);
  invalidateContactsSurfacesLight(ref);
  invalidateCatalogSurfacesLight(ref);
  invalidateTradePurchaseCaches(ref);
  invalidateUserManagementCaches(ref);
  bumpBusinessDataWriteRevision(ref);
}

void invalidateWorkspaceSeedData(dynamic ref) {
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(catalogItemsListProvider);
  invalidateTradePurchaseCaches(ref);
  bumpBusinessDataWriteRevision(ref);
}

/// Catalog item ids linked on a purchase (for targeted cache bust after delete).
Set<String> catalogItemIdsFromPurchase(TradePurchase purchase) => {
      for (final ln in purchase.lines)
        if ((ln.catalogItemId ?? '').trim().isNotEmpty) ln.catalogItemId!.trim(),
    };

/// Catalog ids from API purchase JSON (`lines[].catalog_item_id`).
Set<String> catalogItemIdsFromTradeJson(Map<String, dynamic> body) {
  final ids = <String>{};
  for (final raw in body['lines'] as List? ?? const []) {
    if (raw is! Map) continue;
    final line = Map<String, dynamic>.from(raw);
    final cid = line['catalog_item_id']?.toString().trim() ?? '';
    if (cid.isNotEmpty) ids.add(cid);
  }
  return ids;
}

/// After staff verify / owner commit — refresh SYS everywhere when stock landed.
void syncPurchaseStockAfterVerify(
  dynamic ref, {
  required String purchaseId,
  required Map<String, dynamic> verifyResponse,
}) {
  final ids = catalogItemIdsFromTradeJson(verifyResponse);
  final status = (verifyResponse['delivery_status']?.toString() ?? '')
      .trim()
      .toLowerCase();
  if (status == 'stock_committed') {
    invalidateAfterDeliveryCommit(
      ref,
      purchaseId: purchaseId,
      affectedItemIds: ids,
    );
  } else {
    invalidateAfterDeliveryVerify(
      ref,
      purchaseId: purchaseId,
      affectedItemIds: ids,
    );
  }
}

/// Any purchase API mutation (verify, commit, revert) — single entry for UI refresh.
void syncPurchaseStockFromPurchaseJson(
  dynamic ref, {
  required String purchaseId,
  required Map<String, dynamic> body,
}) {
  syncPurchaseStockAfterVerify(ref, purchaseId: purchaseId, verifyResponse: body);
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
}

/// After soft-delete: bust stock, item detail, delivery pipeline, and aggregates.
void invalidateAfterPurchaseDelete(
  dynamic ref, {
  TradePurchase? purchase,
  String? purchaseId,
  Iterable<String> extraItemIds = const [],
}) {
  final ids = {
    if (purchase != null) ...catalogItemIdsFromPurchase(purchase),
    ...extraItemIds.where((id) => id.trim().isNotEmpty),
  };
  invalidateWarehouseSurfacesLight(ref);
  for (final id in ids) {
    invalidateWarehouseSurfacesLight(ref, itemId: id);
  }
  emitBusinessWriteEvent(ref, kind: 'purchase', affectedItemIds: ids);
  invalidateBusinessAggregates(ref);
  final pid = purchase?.id ?? purchaseId;
  if (pid != null && pid.isNotEmpty) {
    ref.invalidate(tradePurchaseDetailProvider(pid));
  }
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(staffPendingDeliveriesProvider);
  ref.invalidate(homeStockAttentionCountProvider);
  invalidateTradePurchaseCaches(ref);
  bumpBusinessDataWriteRevision(ref);
}

/// Purchase mutations: warehouse lists + financial aggregates (debounced).
void invalidatePurchaseWorkspace(
  dynamic ref, {
  Set<String>? affectedItemIds,
}) {
  final ids = affectedItemIds ?? const <String>{};
  invalidateWarehouseSurfacesLight(ref);
  for (final id in ids) {
    if (id.isEmpty) continue;
    invalidateWarehouseSurfacesLight(ref, itemId: id);
  }
  emitBusinessWriteEvent(ref, kind: 'purchase', affectedItemIds: ids);
  invalidateBusinessAggregates(ref);
}

void _invalidateStockAuditFeeds(dynamic ref) {
  ref.invalidate(stockChangesFeedProvider);
  ref.invalidate(stockAuditPeriodProvider);
  ref.invalidate(homeRecentActivityFeedProvider);
  final n = DateTime.now();
  ref.invalidate(stockAuditDayProvider(DateTime(n.year, n.month, n.day)));
}

/// Catalog lists on pushed routes — no full KPI storm.
void invalidateCatalogSurfacesLight(dynamic ref) {
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(catalogItemsListProvider);
}

/// Contacts hub lists — suppliers, brokers, enriched rows.
void invalidateContactsSurfacesLight(dynamic ref) {
  ref.invalidate(contactsSuppliersEnrichedProvider);
  ref.invalidate(contactsBrokersEnrichedProvider);
  ref.invalidate(contactsCategoriesProvider);
  ref.invalidate(contactsItemsProvider);
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
}

/// Purchase history tab pull / tab return — not full workspace storm.
void invalidatePurchaseListSurfacesLight(dynamic ref) {
  invalidateTradePurchaseCaches(ref);
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(staffPendingDeliveriesProvider);
}

/// User-initiated stock/catalog writes — light warehouse bust + financial KPIs.
void invalidateWarehouseSurfaces(dynamic ref, {String? itemId}) {
  invalidateWarehouseSurfacesLight(ref, itemId: itemId);
  if (itemId != null && itemId.isNotEmpty) {
    emitBusinessWriteEvent(
      ref,
      kind: 'stock',
      affectedItemIds: {itemId},
    );
  }
  invalidateCatalogSurfacesLight(ref);
  invalidateBusinessAggregates(ref);
}

/// Item-scoped bust — detail/activity only (no full list refetch storm).
void invalidateWarehouseItemSurfacesLight(dynamic ref, {required String itemId}) {
  if (itemId.isEmpty) return;
  ref.invalidate(stockItemDetailProvider(itemId));
  ref.invalidate(stockItemIntelligenceProvider(itemId));
  ref.invalidate(stockItemActivityProvider(itemId));
  ref.invalidate(itemDetailBundleProvider(itemId));
  ref.invalidate(tradePurchasesForItemProvider(itemId));
}

/// Patches a single item row without busting [stockListProvider] (no list flash).
void patchStockItemInCache(
  dynamic ref,
  String itemId,
  Map<String, dynamic> newValues,
) {
  if (itemId.isEmpty) return;
  if (newValues.isNotEmpty) {
    applyStockListRowPatch(ref, itemId: itemId, patch: newValues);
  }
  emitBusinessWriteEvent(
    ref,
    kind: 'stock_patch',
    affectedItemIds: {itemId},
  );
  invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
}

/// Background/realtime/home poll: refresh stock + alerts only (no KPI storm).
void invalidateWarehouseSurfacesLight(dynamic ref, {String? itemId}) {
  // Keep [stockListCacheProvider] entries alive so Stock tab does not flash
  // empty on every write/realtime tick — list re-reads cache when query matches.
  ref.invalidate(stockListProvider);
  ref.invalidate(stockDeliveryIndicatorCountsProvider);
  ref.invalidate(bulkStockListProvider);
  ref.invalidate(stockTotalsProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(staffLowStockAlertsProvider);
  ref.invalidate(lowStockByCategoryProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(warehouseAlertsProvider);
  ref.invalidate(stockAlertCountsProvider);
  ref.invalidate(stockLowTopHomeProvider);
  ref.invalidate(stockVariancesTodayProvider);
  _invalidateStockAuditFeeds(ref);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(lowStockOperationsSummaryProvider);
  ref.invalidate(lowStockOperationsPageProvider);
  invalidateCatalogSurfacesLight(ref);
  if (itemId != null && itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
  }
}

void invalidateNotificationSurfaces(dynamic ref) {
  ref.invalidate(appNotificationsListProvider);
  ref.invalidate(appNotificationUnreadCountProvider);
}

/// Staff delivery lists, pipeline KPIs, and owner home — without full financial KPI storm.
void invalidateStaffDeliverySurfacesLight(dynamic ref) {
  ref.invalidate(deliveryPipelineProvider);
  invalidateTradePurchaseCaches(ref);
  ref.invalidate(staffPendingDeliveriesProvider);
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffTodaySummaryProvider);
  ref.invalidate(stockListProvider);
  invalidateStaffHomeSurfacesLight(ref);
}

/// Full staff + owner delivery refresh after verify/commit.
void invalidateStaffDeliverySurfaces(dynamic ref) {
  invalidateStaffDeliverySurfacesLight(ref);
  ref.invalidate(homeOwnerPeriodDashboardProvider);
}

/// Staff submitted warehouse counts — purchase/delivery status only (no stock delta).
void invalidateAfterDeliveryVerify(
  dynamic ref, {
  required String purchaseId,
  Set<String>? affectedItemIds,
}) {
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  invalidateStaffDeliverySurfacesLight(ref);
  invalidateWarehouseSurfacesLight(ref);
  for (final id in affectedItemIds ?? const <String>{}) {
    if (id.isEmpty) continue;
    invalidateWarehouseSurfacesLight(ref, itemId: id);
  }
  invalidateTradePurchaseCaches(ref);
  forceRefreshOwnerHomeDashboard(ref);
  bumpBusinessDataWriteRevision(ref);
}

/// Owner committed delivery to stock — bust warehouse, reports, and delivery pipeline.
void invalidateAfterDeliveryCommit(
  dynamic ref, {
  required String purchaseId,
  Set<String>? affectedItemIds,
}) {
  invalidatePurchaseWorkspace(ref, affectedItemIds: affectedItemIds);
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  invalidateStaffDeliverySurfaces(ref);
  ref.invalidate(homeStockAttentionCountProvider);
  forceRefreshOwnerHomeDashboard(ref);
  bumpBusinessDataWriteRevision(ref);
}
