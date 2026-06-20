import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart';
import 'home_owner_dashboard_providers.dart';
import 'analytics_breakdown_providers.dart';
import 'api_read_snapshots.dart';
import 'business_write_event.dart';
import 'business_write_revision.dart';
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
import 'server_notifications_provider.dart'
    show
        appNotificationUnreadCountProvider,
        appNotificationsListProvider,
        appNotificationsSummaryProvider;
import 'warehouse_alerts_provider.dart';
import 'deferred_invalidation.dart'
    show deferInvalidateDelayed;
import '../auth/provider_api_guard.dart' show resolveInvalidationContainer;

// Debounce guard: prevent stampede when called from multiple sources within 400ms.
Timer? _invalidateDebounce;
Timer? _invalidateTier2;
Timer? _invalidateTier3;
const _invalidateDebounceMs = 250;

/// Immediate owner home refresh after writes (bypasses debounced aggregate gap).
void forceRefreshOwnerHomeDashboard(dynamic ref) {
  bustHomeDashboardVolatileCaches();
  bustHomeShellReportsInflight();
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(homeRecentActivityFeedProvider);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(homeStockAttentionCountProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(deliveryPipelineProvider);
}

/// Mark Reports stale without refetching analytics providers off-tab.
void markReportsDirty(dynamic ref) {
  markReportsPurchasesNeedsLiveFetch(ref);
}

/// Live refetch of Reports tab providers (call when Reports is visible).
void invalidateAnalyticsDataLive(dynamic ref) {
  invalidateAnalyticsDataLiveFromContainer(resolveInvalidationContainer(ref));
}

void invalidateAnalyticsDataLiveFromContainer(ProviderContainer container) {
  container.invalidate(analyticsKpiProvider);
  container.invalidate(analyticsDailyProfitProvider);
  container.invalidate(analyticsItemsTableProvider);
  container.invalidate(analyticsCategoriesTableProvider);
  container.invalidate(analyticsTypesTableProvider);
  container.invalidate(analyticsSuppliersTableProvider);
  container.invalidate(analyticsBrokersTableProvider);
  container.invalidate(analyticsBestSupplierInsightProvider);
  container.invalidate(fullReportsInsightsProvider);
  container.invalidate(fullReportsGoalsProvider);
  container.invalidate(reportsPriorPeriodDeltaProvider);
  container.invalidate(reportsPurchasesPayloadProvider);
  container.invalidate(reportsPeriodComparisonProvider);
  container.invalidate(reportsMovementSummaryProvider);
}

/// KPIs and tables that depend on [analyticsDateRangeProvider] and/or entries.
/// [ref] is any Riverpod `Ref` / `WidgetRef` with `invalidate`.
void invalidateAnalyticsData(dynamic ref) {
  markReportsDirty(ref);
  invalidateAnalyticsDataLive(ref);
}

/// After purchases, entries, or other business writes, bust derived KPIs so
/// Home, Reports, Contacts KPIs, and lists do not show stale numbers.
void invalidateBusinessAggregates(dynamic ref) {
  ProviderContainer container;
  try {
    container = resolveInvalidationContainer(ref);
  } catch (_) {
    return;
  }
  _invalidateDebounce?.cancel();
  _invalidateDebounce = Timer(
    const Duration(milliseconds: _invalidateDebounceMs),
    () {
      _invalidateDebounce = null;
      _doInvalidateBusinessAggregates(container);
    },
  );
}

void _invalidateCatalogSurfacesFromContainer(ProviderContainer container) {
  container.invalidate(itemCategoriesListProvider);
  container.invalidate(catalogItemsListProvider);
}

void _invalidateContactsSurfacesFromContainer(ProviderContainer container) {
  container.invalidate(contactsSuppliersEnrichedProvider);
  container.invalidate(contactsBrokersEnrichedProvider);
  container.invalidate(contactsCategoriesProvider);
  container.invalidate(contactsItemsProvider);
  container.invalidate(suppliersListProvider);
  container.invalidate(brokersListProvider);
}

void _doInvalidateBusinessAggregates(ProviderContainer container) {
  _invalidateTier2?.cancel();
  _invalidateTier3?.cancel();

  bustHomeDashboardVolatileCaches();
  bustHomeShellReportsInflight();
  bustReportsPurchasesInflight();
  final session = container.read(sessionProvider);
  if (session != null) {
    unawaited(
      OfflineStore.bustTradeAggregateCachesForBusiness(session.primaryBusiness.id),
    );
  }
  markReportsDirty(container);

  final branch = container.read(shellCurrentBranchProvider);
  final onHome = branch == ShellBranch.home;
  final onReports = branch == ShellBranch.reports;

  // Tier 1 — critical counts (immediate).
  container.invalidate(deliveryPipelineProvider);
  if (onHome) {
    container.invalidate(homeInventorySummaryProvider);
  }
  container.invalidate(appNotificationsSummaryProvider);
  bumpBusinessDataWriteRevision(container);

  // Tier 2 — lists + home dashboard after DB write propagation (~400ms).
  // [bustHomeDashboardVolatileCaches] already ran above; invalidate so the
  // notifier rebuilds and schedules a fresh pull (avoids stale KPIs while still
  // on Home after a save).
  _invalidateTier2 = Timer(const Duration(milliseconds: 400), () {
    _invalidateTier2 = null;
    invalidateTradePurchaseCachesFromContainer(container);
    _invalidateCatalogSurfacesFromContainer(container);
    _invalidateContactsSurfacesFromContainer(container);
    container.invalidate(businessUsersListProvider);
    container.invalidate(homeDashboardDataProvider);
    container.invalidate(homeShellReportsProvider);
    if (onHome) {
      container.invalidate(homeRecentActivityFeedProvider);
      container.invalidate(homeStockAttentionCountProvider);
    }
  });

  // Tier 3 — heavy aggregates (~1.5s), reports only.
  _invalidateTier3 = Timer(const Duration(milliseconds: 1500), () {
    _invalidateTier3 = null;
    if (onReports) {
      invalidateAnalyticsDataLiveFromContainer(container);
    }
  });
}

/// Catalog item field save — lists + item detail only (no reports/home storm).
void invalidateCatalogItemSaveSurfaces(
  dynamic ref, {
  required String itemId,
}) {
  invalidateCatalogSurfacesLight(ref);
  if (itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
    emitBusinessWriteEvent(
      ref,
      kind: 'stock',
      affectedItemIds: {itemId},
    );
  }
  bumpBusinessDataWriteRevision(ref);
}

/// After catalog item create — refresh lists without home/reports storm.
void invalidateCatalogCreateSurfaces(dynamic ref, {String? itemId}) {
  invalidateCatalogSurfacesLight(ref);
  ref.invalidate(categoryTypesIndexProvider);
  if (itemId != null && itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
    emitBusinessWriteEvent(
      ref,
      kind: 'stock',
      affectedItemIds: {itemId},
    );
  }
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
}

/// Payment / paid flag / share-only purchase edits — no warehouse list storm.
void invalidatePurchaseMetadataLight(
  dynamic ref, {
  String? purchaseId,
}) {
  invalidateTradePurchaseCaches(ref);
  ref.invalidate(deliveryPipelineProvider);
  if (purchaseId != null && purchaseId.isNotEmpty) {
    ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  }
  invalidateBusinessAggregates(ref);
}

/// Purchase mutations: targeted list/home refresh (no full warehouse storm).
void invalidatePurchaseWorkspace(
  dynamic ref, {
  Set<String>? affectedItemIds,
  bool createOnly = false,
}) {
  final ids = affectedItemIds ?? const <String>{};
  if (createOnly) {
    invalidatePurchaseListSurfacesLight(ref);
    emitBusinessWriteEvent(ref, kind: 'purchase', affectedItemIds: ids);
    forceRefreshOwnerHomeDashboard(ref);
    return;
  }
  for (final id in ids) {
    if (id.isEmpty) continue;
    invalidateWarehouseItemSurfacesLight(ref, itemId: id);
  }
  invalidatePurchaseListSurfacesLight(ref);
  emitBusinessWriteEvent(ref, kind: 'purchase', affectedItemIds: ids);
  invalidateBusinessAggregates(ref);
  forceRefreshOwnerHomeDashboard(ref);
}

void _invalidateStockAuditFeeds(dynamic ref) {
  bustStockAuditRecentSnapshot(ref);
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
  ref.invalidate(tradePurchasesForItemProvider(itemId));
}

/// Patches a single item row without busting [stockListProvider] (no list flash).
void applyStockListRowPatchAndEmit(
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
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(stockShellBundleProvider);
}

/// Background/realtime/home poll: refresh stock + alerts only (no KPI storm).
void invalidateWarehouseSurfacesLight(dynamic ref, {String? itemId, bool skipLowStockOps = false}) {
  markWarehouseGlobalInvalidated(ref);
  // Keep [stockListCacheProvider] entries alive so Stock tab does not flash
  // empty on every write/realtime tick — list re-reads cache when query matches.
  ref.invalidate(stockShellBundleProvider);
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
  if (!skipLowStockOps) {
    ref.invalidate(lowStockOperationsSummaryProvider);
    ref.invalidate(lowStockOperationsPageProvider);
    ref.invalidate(lowStockOperationsGroupedProvider);
  }
  if (itemId != null && itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
  }
}

/// Opening stock bulk/single save — row patch reconcile without deferred list storm.
void invalidateOpeningStockSaveSurfaces(
  dynamic ref, {
  Iterable<String> itemIds = const [],
}) {
  final ids = itemIds.where((id) => id.isNotEmpty).toList();
  if (ids.isEmpty) {
    ref.invalidate(stockListProvider);
  } else {
    for (final id in ids) {
      unawaited(patchStockItemInCache(ref, itemId: id));
      invalidateWarehouseItemSurfacesLight(ref, itemId: id);
    }
  }
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(openingStockSetupProvider);
  ref.invalidate(openingStockMissingProvider);
  ref.invalidate(stockChangesFeedProvider);
}

/// Tiered stock row save — patch overlay + single-row reconcile (no deferred list storm).
void invalidateStockRowSaveSurfaces(
  dynamic ref, {
  required String itemId,
  bool reorderAlert = false,
  bool deferFullList = true,
  bool immediateListReconcile = false,
  bool refreshItemDetail = false,
}) {
  if (refreshItemDetail && itemId.isNotEmpty) {
    deferInvalidateDelayed(ref, stockItemDetailProvider(itemId));
    deferInvalidateDelayed(ref, stockItemActivityProvider(itemId));
  }
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(stockFilteredStatusCountsProvider);
  ref.invalidate(stockDeliveryIndicatorCountsProvider);
  if (immediateListReconcile) {
    ref.invalidate(stockListProvider);
  } else if (itemId.isNotEmpty) {
    unawaited(patchStockItemInCache(ref, itemId: itemId));
  } else if (deferFullList) {
    ref.invalidate(stockListProvider);
  }
  if (reorderAlert) {
    ref.invalidate(homeInventorySummaryProvider);
    ref.invalidate(homeStockAttentionCountProvider);
    ref.invalidate(staffLowStockAlertsProvider);
    ref.invalidate(warehouseAlertsProvider);
  }
}

/// After stock save — keep optimistic patch visible; defer full list refetch.
///
/// [light]: quick row edit from stock list — skip item-detail/home/bulk refetch
/// storm; keep ETag so deferred list reconcile may 304.
void invalidateWarehouseSurfacesAfterStockWrite(
  dynamic ref, {
  String? itemId,
  bool deferFullList = true,
  bool light = false,
}) {
  if (light && itemId != null && itemId.isNotEmpty) {
    invalidateStockRowSaveSurfaces(
      ref,
      itemId: itemId,
      deferFullList: deferFullList,
      immediateListReconcile: !deferFullList,
    );
    return;
  }
  if (!light) {
    if (itemId != null && itemId.isNotEmpty) {
      invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
    }
    ref.invalidate(homeInventorySummaryProvider);
    ref.invalidate(homeStockAttentionCountProvider);
    ref.invalidate(staffTodayActivityProvider);
    ref.invalidate(staffTodaySummaryProvider);
    deferInvalidateDelayed(ref, bulkStockListProvider, delay: const Duration(seconds: 2));
    deferInvalidateDelayed(ref, stockOnHandTotalsProvider, delay: const Duration(seconds: 2));
    deferInvalidateDelayed(ref, staffLowStockAlertsProvider, delay: const Duration(seconds: 2));
    deferInvalidateDelayed(ref, warehouseAlertsProvider, delay: const Duration(seconds: 2));
  }
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(stockFilteredStatusCountsProvider);
  if (deferFullList) {
    if (itemId != null && itemId.isNotEmpty) {
      unawaited(patchStockItemInCache(ref, itemId: itemId));
    } else {
      ref.invalidate(stockListProvider);
    }
    if (!light) {
      ref.invalidate(stockDeliveryIndicatorCountsProvider);
    }
  } else if (!light) {
    ref.invalidate(stockListProvider);
    ref.invalidate(stockDeliveryIndicatorCountsProvider);
    ref.invalidate(bulkStockListProvider);
    ref.invalidate(stockOnHandTotalsProvider);
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
  for (final id in affectedItemIds ?? const <String>{}) {
    if (id.isEmpty) continue;
    invalidateWarehouseItemSurfacesLight(ref, itemId: id);
  }
  ref.invalidate(homeRecentActivityFeedProvider);
  ref.invalidate(deliveryPipelineProvider);
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
  invalidateWarehouseSurfacesLight(ref);
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  invalidateStaffDeliverySurfaces(ref);
  ref.invalidate(homeStockAttentionCountProvider);
  bumpBusinessDataWriteRevision(ref);
}
