import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/session.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../presentation/operational_reports_section.dart';
import '../presentation/reports_overview_chart_section.dart';
import '../presentation/widgets/reports_insights_strip.dart';
import '../shell/reports_layout.dart';
import '../widgets/reports_kpi_row.dart';

/// Overview tab: KPI row + insight chips + full-width charts.
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
    final session = ref.watch(sessionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportsKpiRow(
            totals: agg.totals,
            itemCount: agg.itemsAll.length,
            supplierCount: agg.suppliers.length,
          ),
          const SizedBox(height: 8),
          ReportsInsightsStrip(agg: agg),
          const SizedBox(height: 8),
          SizedBox(
            height: kReportsChartMinHeight,
            child: ReportsOverviewChartSection(
              agg: agg,
              viewportHeight: kReportsChartMinHeight,
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
          ),
          if (session != null && sessionCanSeeFinancials(session))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: OperationalReportsSection(),
            ),
        ],
      ),
    );
  }
}
