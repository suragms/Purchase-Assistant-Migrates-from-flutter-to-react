import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart';
import 'cloud_expense_provider.dart';
import 'analytics_breakdown_providers.dart';
import 'business_write_revision.dart';
import 'analytics_kpi_provider.dart';
import 'reports_provider.dart';
import 'brokers_list_provider.dart';
import 'catalog_providers.dart';
import 'contacts_hub_provider.dart';
import 'dashboard_provider.dart';
import 'full_reports_insights_providers.dart';
import 'home_insights_provider.dart';
import 'reports_prior_period_provider.dart';
import 'suppliers_list_provider.dart';
import 'trade_purchases_provider.dart';
import 'deferred_invalidation.dart' show deferInvalidateDelayed;
import 'home_owner_dashboard_providers.dart' show homeInventorySummaryProvider;
import 'item_detail_providers.dart';
import 'staff_home_providers.dart'
    show staffTodayActivityProvider, staffTodaySummaryProvider;
import 'stock_providers.dart';

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
}

/// After purchases, entries, or other business writes, bust derived KPIs so
/// Home, Reports, Contacts KPIs, and lists do not show stale numbers.
///
/// Also invalidates the keepAlive supplier/broker list providers so pickers
/// and preference JSON always reflect the latest server state.
///
/// [ref] is any Riverpod `Ref` / `WidgetRef` with `invalidate`.
void invalidateBusinessAggregates(dynamic ref) {
  invalidateAnalyticsData(ref);
  ref.invalidate(dashboardProvider);
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(cloudCostProvider);
  ref.invalidate(homeInsightsProvider);
  ref.invalidate(contactsSuppliersEnrichedProvider);
  ref.invalidate(contactsBrokersEnrichedProvider);
  ref.invalidate(contactsCategoriesProvider);
  ref.invalidate(contactsItemsProvider);
  // keepAlive list providers — must be explicitly busted after any write that
  // touches supplier/broker rows (purchase save, item wizard, entry create).
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(catalogItemsListProvider);
  invalidateTradePurchaseCaches(ref);
  // Open ledger / item-insight screens use local or family providers — nudge
  // them to refetch after any aggregate-invalidating write.
  bumpBusinessDataWriteRevision(ref);
}

/// After workspace **seed** only: refresh list data without refetching every KPI
/// and dashboard tile (avoids a stampede on cold start / bootstrap).
void invalidateWorkspaceSeedData(dynamic ref) {
  ref.invalidate(suppliersListProvider);
  ref.invalidate(brokersListProvider);
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(catalogItemsListProvider);
  invalidateTradePurchaseCaches(ref);
  bumpBusinessDataWriteRevision(ref);
}

/// Bust purchase lists, trade reports, and dashboard KPIs after a purchase
/// mutation (create, update, delete, or cancel). Prefer this over ad-hoc
/// [invalidateTradePurchaseCaches] + [invalidateBusinessAggregates] pairs.
///
/// [invalidateBusinessAggregates] already calls [invalidateTradePurchaseCaches]
/// (purchase list + alert/cache providers) plus [homeDashboardDataProvider],
/// reports insights, KPIs, and supplier/broker lists.
void invalidatePurchaseWorkspace(dynamic ref) {
  invalidateBusinessAggregates(ref);
}

/// Item-scoped bust — detail/activity only (no full list refetch storm).
void invalidateWarehouseItemSurfacesLight(dynamic ref, {required String itemId}) {
  if (itemId.isEmpty) return;
  ref.invalidate(stockItemDetailProvider(itemId));
  ref.invalidate(stockItemIntelligenceProvider(itemId));
  ref.invalidate(stockItemActivityProvider(itemId));
  ref.invalidate(itemDetailBundleProvider(itemId));
}

/// Background/realtime: refresh stock + alerts (immediate full list refetch).
void invalidateWarehouseSurfacesLight(dynamic ref, {String? itemId}) {
  clearStockListEtagCache(ref);
  ref.invalidate(stockListProvider);
  ref.invalidate(bulkStockListProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(homeInventorySummaryProvider);
  if (itemId != null && itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
  }
}

/// After stock save — keep optimistic patch visible; defer full list refetch.
void invalidateWarehouseSurfacesAfterStockWrite(
  dynamic ref, {
  String? itemId,
  bool deferFullList = true,
}) {
  clearStockListEtagCache(ref);
  if (itemId != null && itemId.isNotEmpty) {
    invalidateWarehouseItemSurfacesLight(ref, itemId: itemId);
  }
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffTodaySummaryProvider);
  if (deferFullList) {
    const listDelay = Duration(seconds: 1);
    deferInvalidateDelayed(ref, stockListProvider, delay: listDelay);
    deferInvalidateDelayed(ref, bulkStockListProvider, delay: listDelay);
    deferInvalidateDelayed(ref, stockOnHandTotalsProvider, delay: listDelay);
  } else {
    ref.invalidate(stockListProvider);
    ref.invalidate(bulkStockListProvider);
    ref.invalidate(stockOnHandTotalsProvider);
  }
}

/// Undo, bulk archive, offline replay — immediate list + detail refresh.
void invalidateWarehouseSurfaces(dynamic ref, {String? itemId}) {
  invalidateWarehouseSurfacesAfterStockWrite(
    ref,
    itemId: itemId,
    deferFullList: false,
  );
}
