import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';
import 'home_analytics_comparison_strip.dart';
import 'home_analytics_helpers.dart';
import 'home_analytics_ranked_list.dart';
import 'home_analytics_ring.dart';
import 'home_analytics_summary_row.dart';
import 'home_analytics_tabs.dart';
import 'home_inventory_summary_strip.dart';

/// Owner preference: analytics card expanded on home.
final homeAnalyticsExpandedProvider = StateProvider<bool>((_) => true);

/// Unified analytics rectangle: inventory summary, tabs, ring, ranked list.
class HomeAnalyticsCard extends ConsumerStatefulWidget {
  const HomeAnalyticsCard({super.key});

  @override
  ConsumerState<HomeAnalyticsCard> createState() => _HomeAnalyticsCardState();
}

class _HomeAnalyticsCardState extends ConsumerState<HomeAnalyticsCard> {
  List<HomeAnalyticsSlice>? _lastNonEmptySlices;
  HomeDashboardData? _lastDash;

  @override
  Widget build(BuildContext context) {
    ref.watch(homePeriodProvider);
    ref.watch(homeCustomDateRangeProvider);

    final dashState = ref.watch(homeDashboardDataProvider);
    final dash = dashState.snapshot.data;
    if (!dash.isEmpty) _lastDash = dash;

    final displayDash =
        (dashState.refreshing && dash.isEmpty && _lastDash != null)
            ? _lastDash!
            : dash;

    final tab = ref.watch(homeBreakdownTabProvider);
    final shellAsync = ref.watch(homeShellReportsProvider);
    final invAsync = ref.watch(homeInventorySummaryProvider);
    final expanded = ref.watch(homeAnalyticsExpandedProvider);

    final inv = invAsync.valueOrNull ?? HomeInventorySummary.empty;
    final shell = shellAsync.valueOrNull;

    if (dashState.refreshing && dash.isEmpty && _lastDash == null) {
      return _cardShell(
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: ListSkeleton(rowCount: 4, rowHeight: 56),
        ),
      );
    }

    if (shellAsync.hasError && dash.isEmpty && _lastDash == null) {
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

    var slices = homeAnalyticsSlicesForTab(
      tab: tab,
      dash: displayDash,
      shell: shell,
    );
    if (slices.isNotEmpty) {
      _lastNonEmptySlices = slices;
    } else if (dashState.refreshing &&
        _lastNonEmptySlices != null &&
        _lastNonEmptySlices!.isNotEmpty) {
      slices = _lastNonEmptySlices!;
    }

    final shellLoading = shellAsync.isLoading &&
        tab != HomeBreakdownTab.category &&
        slices.isEmpty;

    final mq = MediaQuery.sizeOf(context);
    final layoutWidth = mq.width - 32 - 28;

    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => ref
                  .read(homeAnalyticsExpandedProvider.notifier)
                  .state = !expanded,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Text(
                    'Analytics',
                    style: HexaDsType.bodySm(context).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 22,
                    color: HexaDsColors.textMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            HomeAnalyticsSummaryRow(
              inventory: inv,
              loading: invAsync.isLoading && !invAsync.hasValue,
            ),
            const SizedBox(height: 10),
            HomeInventorySummaryStrip(
              inventory: inv,
              dashboard: displayDash,
              inventoryLoading: invAsync.isLoading && !invAsync.hasValue,
              purchasedLoading: dashState.refreshing && dash.isEmpty,
            ),
            const SizedBox(height: 8),
            const HomeAnalyticsComparisonStrip(),
            if (expanded) ...[
              const SizedBox(height: 10),
              const HomeAnalyticsTabs(),
              const SizedBox(height: 10),
              if (shellLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                HomeAnalyticsRing(
                  dash: displayDash,
                  slices: slices,
                  tab: tab,
                  layoutWidth: layoutWidth,
                  screenHeight: mq.height,
                ),
                const SizedBox(height: 10),
                HomeAnalyticsRankedList(
                  slices: slices,
                  tab: tab,
                  dash: displayDash,
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              HomeAnalyticsRing(
                dash: displayDash,
                slices: slices,
                tab: tab,
                layoutWidth: layoutWidth,
                screenHeight: mq.height,
                mini: true,
              ),
            ],
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
