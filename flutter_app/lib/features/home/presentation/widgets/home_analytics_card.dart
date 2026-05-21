import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import 'home_analytics_helpers.dart';
import 'home_analytics_ranked_list.dart';
import 'home_analytics_ring.dart';
import 'home_analytics_summary_row.dart';
import 'home_analytics_tabs.dart';

/// Unified analytics rectangle: inventory summary, tabs, ring, ranked list.
class HomeAnalyticsCard extends ConsumerWidget {
  const HomeAnalyticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(homeDashboardDataProvider);
    final dash = dashState.snapshot.data;
    final tab = ref.watch(homeBreakdownTabProvider);
    final shellAsync = ref.watch(homeShellReportsProvider);
    final invAsync = ref.watch(homeInventorySummaryProvider);

    final inv = invAsync.valueOrNull ?? HomeInventorySummary.empty;
    final shell = shellAsync.valueOrNull;

    if (dashState.refreshing && dash.isEmpty) {
      return _cardShell(
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (shellAsync.hasError && dash.isEmpty) {
      return _cardShell(
        child: FriendlyLoadError(
          message: 'Could not load analytics',
          onRetry: () {
            ref.invalidate(homeDashboardDataProvider);
            ref.invalidate(homeShellReportsProvider);
            ref.invalidate(homeInventorySummaryProvider);
          },
        ),
      );
    }

    final slices = homeAnalyticsSlicesForTab(
      tab: tab,
      dash: dash,
      shell: shell,
    );

    final mq = MediaQuery.sizeOf(context);

    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeAnalyticsSummaryRow(
              inventory: inv,
              loading: invAsync.isLoading && !invAsync.hasValue,
            ),
            const SizedBox(height: 12),
            const HomeAnalyticsTabs(),
            const SizedBox(height: 12),
            HomeAnalyticsRing(
              dash: dash,
              slices: slices,
              layoutWidth: mq.width - 32 - 28,
              screenHeight: mq.height,
            ),
            const SizedBox(height: 12),
            HomeAnalyticsRankedList(slices: slices, tab: tab),
          ],
        ),
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: child,
    );
  }
}
