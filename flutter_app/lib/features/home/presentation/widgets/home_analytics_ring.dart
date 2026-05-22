import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../widgets/spend_ring_chart.dart';
import '../home_spend_ring_diameter.dart';
import 'home_analytics_helpers.dart';
import 'home_formatters.dart';

/// Large period-scoped donut with profit + units in center.
class HomeAnalyticsRing extends ConsumerWidget {
  const HomeAnalyticsRing({
    super.key,
    required this.dash,
    required this.slices,
    required this.tab,
    required this.layoutWidth,
    required this.screenHeight,
    this.mini = false,
  });

  final HomeDashboardData dash;
  final List<HomeAnalyticsSlice> slices;
  final HomeBreakdownTab tab;
  final double layoutWidth;
  final double screenHeight;
  final bool mini;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diameter = mini
        ? 72.0
        : computeHomeSpendRingDiameter(
            screenHeight: screenHeight,
            layoutMaxWidth: layoutWidth,
          );
    final stroke = mini ? 10.0 : 14.0;
    final values = slices.map((s) => s.amount).where((a) => a > 0).toList();
    final colors =
        slices.where((s) => s.amount > 0).map((s) => s.color).toList();
    final hasRingData =
        values.isNotEmpty && values.fold<double>(0, (a, b) => a + b) > 0;

    final profit = dash.totalProfit;
    final pct = dash.profitPercent;
    final pctLabel = pct != null
        ? '(${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)'
        : '';
    final units = homeDashboardUnitsLine(dash);
    final emptyHint = homeAnalyticsEmptyHint(tab, dash);

    if (!hasRingData) {
      final showPeriodTotals = dash.purchaseCount > 0;
      return Center(
        child: SpendRingChart(
          diameter: diameter,
          strokeWidth: stroke,
          values: const [1],
          colors: const [Color(0xFFE2E8F0)],
          centerChild: mini
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showPeriodTotals) ...[
                      Text(
                        'Profit',
                        style: HexaDsType.labelCaps(context).copyWith(
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        homeInr(profit),
                        style: HexaDsType.bodySm(context).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (units.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          units,
                          textAlign: TextAlign.center,
                          style: HexaDsType.bodySm(context).copyWith(
                            fontSize: 10,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                    ],
                    Text(
                      emptyHint,
                      textAlign: TextAlign.center,
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    void onTap(int index) {
      if (index < 0 || index >= slices.length) return;
      final slice = slices[index];
      final q = <String, String>{'tab': tab.name};
      if (slice.title.isNotEmpty) q['focus'] = slice.title;
      context.push(Uri(path: '/reports', queryParameters: q).toString());
    }

    return Center(
      child: SpendRingChart(
        diameter: diameter,
        strokeWidth: stroke,
        values: values,
        colors: colors,
        centerLine1: mini ? null : 'Profit',
        centerLine2: mini ? null : homeInr(profit),
        centerLine3: mini || pctLabel.isEmpty ? null : pctLabel,
        centerLine4: mini || units.isEmpty ? null : units,
        onSectionTap: mini ? null : onTap,
      ),
    );
  }
}
