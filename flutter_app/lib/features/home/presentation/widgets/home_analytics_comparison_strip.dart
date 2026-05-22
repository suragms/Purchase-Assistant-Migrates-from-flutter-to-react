import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/reports_prior_period_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'home_formatters.dart';

/// Period-over-period comparison chips under analytics summary.
class HomeAnalyticsComparisonStrip extends ConsumerWidget {
  const HomeAnalyticsComparisonStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;
    final prior = ref.watch(reportsPriorPeriodDeltaProvider).valueOrNull;
    if (dash.isEmpty && prior == null) return const SizedBox.shrink();

    String deltaLabel(String label, double? pct) {
      if (pct == null) return '$label —';
      final sign = pct >= 0 ? '+' : '';
      return '$label $sign${pct.toStringAsFixed(1)}%';
    }

    final purchasePct = prior?.purchasePctVsPrior();
    final profitPct = prior?.profitPctVsPrior();

    return Row(
      children: [
        Expanded(
          child: _chip(
            context,
            'Purchases',
            homeInr(dash.totalPurchase),
            deltaLabel('vs prior', purchasePct),
            purchasePct != null && purchasePct < 0
                ? HexaColors.loss
                : const Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _chip(
            context,
            'Profit',
            homeInr(dash.totalProfit),
            deltaLabel('vs prior', profitPct),
            profitPct != null && profitPct < 0
                ? HexaColors.loss
                : const Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    String title,
    String value,
    String delta,
    Color deltaColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: HexaDsType.label(10, color: HexaDsColors.textMuted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          Text(
            delta,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: deltaColor),
          ),
        ],
      ),
    );
  }
}
