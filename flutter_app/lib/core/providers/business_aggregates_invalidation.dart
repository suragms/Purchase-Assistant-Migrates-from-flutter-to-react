import 'dart:async';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart';
import 'home_owner_dashboard_providers.dart';
import 'cloud_expense_provider.dart';
import 'analytics_breakdown_providers.dart';
import 'business_write_revision.dart';
import 'analytics_kpi_provider.dart';
import 'reports_provider.dart';
import 'reports_bi_providers.dart';
import 'brokers_list_provider.dart';
import 'catalog_providers.dart';
import 'contacts_hub_provider.dart';
import 'dashboard_provider.dart';
import 'full_reports_insights_providers.dart';
import 'home_insights_provider.dart';
import 'reports_prior_period_provider.dart';
import 'suppliers_list_provider.dart';
import 'trade_purchases_provider.dart';
import 'business_users_provider.dart';
import 'stock_providers.dart';
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
///
/// **Offline / Hive (t18):** Also calls [OfflineStore.bustTradeAggregateCachesForBusiness],
/// which removes keys prefixed `trade_dash|`, `home_shell|`, and `reports_tp|` plus the
/// legacy `dashboard` blob for that business. Pair with [invalidatePurchaseWorkspace]
/// after any trade purchase create/update/delete/cancel/payment patch so Riverpod refetch
/// and on-disk aggregates stay aligned.
///
/// Also invalidates the keepAlive supplier/broker list providers so pickers
/// and preference JSON always reflect the latest server state.
///
/// [ref] is any Riverpod `Ref` / `WidgetRef` with `invalidate`.
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
  ref.invalidate(dashboardProvider);
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeShellReportsProvider);
  ref.invalidate(homeInventorySummaryProvider);
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
  invalidateUserManagementCaches(ref);
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
  invalidateWarehouseSurfaces(ref);
}

/// Home, stock list, bulk print, totals, and warehouse alert chips.
void invalidateWarehouseSurfaces(dynamic ref) {
  invalidateBusinessAggregates(ref);
  ref.invalidate(stockListProvider);
  ref.invalidate(bulkStockListProvider);
  // Family provider: invalidating the family root busts all period keys.
  ref.invalidate(stockTotalsProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(stockItemIntelligenceProvider);
  ref.invalidate(warehouseAlertsProvider);
  ref.invalidate(homeRecentActivityFeedProvider);
  ref.invalidate(stockAlertCountsProvider);
  ref.invalidate(stockLowTopHomeProvider);
  ref.invalidate(stockVariancesTodayProvider);
  bumpBusinessDataWriteRevision(ref);
}
