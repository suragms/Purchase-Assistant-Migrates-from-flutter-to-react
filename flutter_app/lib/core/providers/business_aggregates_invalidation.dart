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

/// KPIs and tables that depend on [analyticsDateRangeProvider] and/or entries.
/// [ref] is any Riverpod `Ref` / `WidgetRef` with `invalidate`.
void invalidateAnalyticsData(dynamic ref) {
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
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(contactsSuppliersEnrichedProvider);
  ref.invalidate(contactsBrokersEnrichedProvider);
  ref.invalidate(contactsCategoriesProvider);
  ref.invalidate(contactsItemsProvider);
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(catalogItemsListProvider);
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
  invalidateTradePurchaseCaches(ref);
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
  invalidateBusinessAggregates(ref);
}

/// Background/realtime/home poll: refresh stock + alerts only (no KPI storm).
void invalidateWarehouseSurfacesLight(dynamic ref, {String? itemId}) {
  ref.invalidate(stockListProvider);
  ref.invalidate(stockListCacheProvider);
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
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(lowStockOperationsSummaryProvider);
  ref.invalidate(lowStockOperationsPageProvider);
  if (itemId != null && itemId.isNotEmpty) {
    ref.invalidate(stockItemDetailProvider(itemId));
    ref.invalidate(stockItemIntelligenceProvider(itemId));
    ref.invalidate(stockItemActivityProvider(itemId));
    ref.invalidate(itemDetailBundleProvider(itemId));
    ref.invalidate(tradePurchasesForItemProvider(itemId));
  }
}

void invalidateNotificationSurfaces(dynamic ref) {
  ref.invalidate(appNotificationsListProvider);
  ref.invalidate(appNotificationUnreadCountProvider);
}

/// Staff submitted warehouse counts — purchase/delivery status only (no stock delta).
void invalidateAfterDeliveryVerify(
  dynamic ref, {
  required String purchaseId,
}) {
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(staffPendingDeliveriesProvider);
  invalidateTradePurchaseCaches(ref);
}

/// Owner committed delivery to stock — bust warehouse, reports, and delivery pipeline.
void invalidateAfterDeliveryCommit(
  dynamic ref, {
  required String purchaseId,
  Set<String>? affectedItemIds,
}) {
  invalidatePurchaseWorkspace(ref, affectedItemIds: affectedItemIds);
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(tradePurchaseDetailProvider(purchaseId));
  ref.invalidate(staffPendingDeliveriesProvider);
  ref.invalidate(homeStockAttentionCountProvider);
  bumpBusinessDataWriteRevision(ref);
}
