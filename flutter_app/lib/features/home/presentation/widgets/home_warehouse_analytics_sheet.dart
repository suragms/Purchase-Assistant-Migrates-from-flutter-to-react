import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/widgets/list_skeleton.dart';
import 'home_analytics_helpers.dart';
import 'home_analytics_ranked_list.dart';
import 'home_analytics_ring.dart';
import 'home_analytics_tabs.dart';

Future<void> showWarehouseAnalyticsSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _WarehouseAnalyticsSheet(),
  );
}

class _WarehouseAnalyticsSheet extends ConsumerWidget {
  const _WarehouseAnalyticsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(homeDashboardDataProvider);
    final shellAsync = ref.watch(homeShellReportsProvider);
    final tab = ref.watch(homeBreakdownTabProvider);
    final mq = MediaQuery.sizeOf(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: 14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: mq.height * 0.82,
          child: dashState.refreshing && dashState.snapshot.data.isEmpty
              ? const ListSkeleton(rowCount: 5, rowHeight: 56)
              : _WarehouseAnalyticsBody(
                  dash: dashState.snapshot.data,
                  shell: shellAsync.valueOrNull,
                  tab: tab,
                  width: mq.width,
                  height: mq.height,
                ),
        ),
      ),
    );
  }
}

class _WarehouseAnalyticsBody extends StatelessWidget {
  const _WarehouseAnalyticsBody({
    required this.dash,
    required this.shell,
    required this.tab,
    required this.width,
    required this.height,
  });

  final HomeDashboardData dash;
  final HomeShellReportsBundle? shell;
  final HomeBreakdownTab tab;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slices = homeAnalyticsSlicesForTab(
      tab: tab,
      dash: dash,
      shell: shell,
    );
    return ListView(
      children: [
        const Text(
          'Warehouse analytics',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const HomeAnalyticsTabs(),
        const SizedBox(height: 12),
        HomeAnalyticsRing(
          dash: dash,
          slices: slices,
          tab: tab,
          layoutWidth: width - 28,
          screenHeight: height,
        ),
        const SizedBox(height: 12),
        HomeAnalyticsRankedList(
          slices: slices,
          tab: tab,
          dash: dash,
          maxRows: 8,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap a ring segment or row to open the matching report. Item drilldown opens from item rows where an item id is available.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}
