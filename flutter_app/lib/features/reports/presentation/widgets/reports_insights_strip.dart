import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/analytics_breakdown_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/operations_providers.dart';
import '../../../../core/providers/reports_bi_providers.dart';
import '../../../../core/reporting/trade_report_aggregate.dart';

/// Rule-based owner insight pills for Reports overview.
class ReportsInsightsStrip extends ConsumerWidget {
  const ReportsInsightsStrip({
    super.key,
    required this.agg,
  });

  final TradeReportAgg agg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pills = <String>[];
    final comparison = ref.watch(reportsPeriodComparisonProvider).valueOrNull;
    final pct = comparison?['purchase_change_pct'];
    if (pct is num && pct.abs() >= 3) {
      pills.add(
        pct > 0
            ? 'Purchases up ${pct.toStringAsFixed(0)}% vs prior period'
            : 'Purchases down ${pct.abs().toStringAsFixed(0)}% vs prior period',
      );
    }
    final cats = ref.watch(analyticsCategoriesTableProvider).valueOrNull ?? [];
    final total = cats.fold<double>(
      0,
      (s, r) => s + coerceToDouble(r['total_purchase'] ?? r['total_amount']),
    );
    if (cats.isNotEmpty && total > 0) {
      final top = cats.first;
      final topAmt = coerceToDouble(top['total_purchase'] ?? top['total_amount']);
      final share = (topAmt / total) * 100;
      if (share >= 40) {
        final nm = top['category_name'] ?? top['category'] ?? 'Category';
        pills.add('$nm dominates ${share.toStringAsFixed(0)}% of spend');
      }
    }
    final ops = ref.watch(operationalReportsProvider).valueOrNull;
    final slow = (ops?['slow_moving'] as List?)?.length ?? 0;
    final dead = (ops?['dead_stock'] as List?)?.length ?? 0;
    if (slow > 0) pills.add('$slow slow-moving items need review');
    if (dead > 0) pills.add('$dead items at dead-stock risk');
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;
    if (dash.pendingDeliveryCount > 0) {
      pills.add('${dash.pendingDeliveryCount} pending deliveries');
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final p in pills.take(6))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0DDD8)),
                  ),
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
