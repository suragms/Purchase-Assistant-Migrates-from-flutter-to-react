import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../presentation/reports_overview_chart_section.dart';
import '../shell/reports_layout.dart';
import '../widgets/reports_overview_kpi_grid.dart';

/// Overview tab: KPI grid first, charts below.
class ReportsOverviewTab extends ConsumerWidget {
  const ReportsOverviewTab({
    super.key,
    required this.agg,
    required this.merged,
    required this.showSkeleton,
    required this.hasFetchError,
    required this.showEmpty,
    required this.purchasesError,
    required this.onRetry,
    required this.onMatchHome,
    required this.onPickRange,
  });

  final TradeReportAgg agg;
  final List<TradePurchase> merged;
  final bool showSkeleton;
  final bool hasFetchError;
  final bool showEmpty;
  final Object? purchasesError;
  final VoidCallback onRetry;
  final VoidCallback onMatchHome;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void goTab(String tab) => context.replace('/reports?tab=$tab');

    final chartH = MediaQuery.sizeOf(context).height.clamp(400.0, 900.0) * 0.38;
    final viewport = chartH.clamp(kReportsChartMinHeight, 420.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportsOverviewKpiGrid(
            agg: agg,
            onTapStock: () => goTab('stock'),
            onTapPurchases: () => goTab('purchase'),
            onTapItems: () => goTab('items'),
          ),
          const SizedBox(height: 8),
          ReportsOverviewChartSection(
            agg: agg,
            viewportHeight: viewport,
            isLoadingInitial: showSkeleton,
            loadFailed: hasFetchError && merged.isEmpty,
            loadError: purchasesError,
            isEmpty: showEmpty,
            canRetry: true,
            hideTopStatRow: true,
            onRetry: onRetry,
            onMatchHome: onMatchHome,
            onPickRange: onPickRange,
          ),
        ],
      ),
    );
  }
}
