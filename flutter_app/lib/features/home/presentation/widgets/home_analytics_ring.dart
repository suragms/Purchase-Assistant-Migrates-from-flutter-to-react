import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../widgets/spend_ring_chart.dart';
import '../home_spend_ring_diameter.dart';
import 'home_analytics_helpers.dart';
import 'home_formatters.dart';

/// Large period-scoped donut with profit + units in center.
class HomeAnalyticsRing extends StatelessWidget {
  const HomeAnalyticsRing({
    super.key,
    required this.dash,
    required this.slices,
    required this.layoutWidth,
    required this.screenHeight,
  });

  final HomeDashboardData dash;
  final List<HomeAnalyticsSlice> slices;
  final double layoutWidth;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    final diameter = computeHomeSpendRingDiameter(
      screenHeight: screenHeight,
      layoutMaxWidth: layoutWidth,
    );
    final values = slices.map((s) => s.amount).where((a) => a > 0).toList();
    final colors = slices
        .where((s) => s.amount > 0)
        .map((s) => s.color)
        .toList();

    if (values.isEmpty || values.fold<double>(0, (a, b) => a + b) <= 0) {
      return Center(
        child: SpendRingChart(
          diameter: diameter,
          strokeWidth: 14,
          values: const [1],
          colors: const [Color(0xFFE2E8F0)],
          centerChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined,
                  size: 28, color: Colors.grey.shade400),
              const SizedBox(height: 6),
              Text(
                'No purchases in period',
                textAlign: TextAlign.center,
                style: HexaDsType.bodySm(context).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final profit = dash.totalProfit;
    final pct = dash.profitPercent;
    final pctLabel = pct != null
        ? '(${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)'
        : '';
    final units = homeDashboardUnitsLine(dash);

    return Center(
      child: SpendRingChart(
        diameter: diameter,
        strokeWidth: 14,
        values: values,
        colors: colors,
        centerLine1: 'Profit',
        centerLine2: homeInr(profit),
        centerLine3: pctLabel.isNotEmpty ? pctLabel : null,
        centerLine4: units.isNotEmpty ? units : null,
      ),
    );
  }
}
