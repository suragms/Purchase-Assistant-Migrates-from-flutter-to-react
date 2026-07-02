import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/unit_utils.dart';
import 'home_bold_metrics_line.dart';
import 'home_formatters.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;

/// Purchase-first hub: quantities first, amount secondary.
class HomePurchaseControlCenter extends ConsumerWidget {
  const HomePurchaseControlCenter({super.key});

  static String _qty(double n) =>
      n.abs() < 0.001 ? '' : formatStockQtyNumber(n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(homePeriodProvider);
    final dashState = ref.watch(homeDashboardDataProvider);
    final session = ref.watch(sessionProvider);
    final showProfit = session != null && sessionHasOwnerDashboard(session);

    if (dashState.refreshing && dashState.snapshot.data == HomeDashboardData.empty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(HexaOp.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HomeSectionSkeleton(rows: 2),
              const SizedBox(height: 8),
              Text(
                'Loading purchase totals…',
                style: HexaOp.caption(context),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () {
                  ref.invalidate(homeDashboardDataProvider);
                  ref.read(homeDashboardDataProvider.notifier).forceStopRefreshing();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final dash = dashState.snapshot.data;
    {
        final unitSegments = <HomeBoldMetricSegment>[];
        if (dash.totalBags > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(dash.totalBags),
            unit: 'bags',
            color: HomeMetricColors.bags,
          ));
        }
        if (dash.totalKg > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(dash.totalKg),
            unit: 'KG',
            color: HomeMetricColors.kg,
          ));
        }
        if (dash.totalBoxes > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(dash.totalBoxes),
            unit: 'boxes',
            color: HomeMetricColors.boxes,
          ));
        }
        if (dash.totalTins > 0.001) {
          unitSegments.add(HomeBoldMetricSegment(
            value: _qty(dash.totalTins),
            unit: 'tins',
            color: HomeMetricColors.tins,
          ));
        }

        final received = dash.receivedDeliveryCount;
        final pending = dash.pendingDeliveryCount;
        final suppliers = dash.supplierCount;
        final brokers = dash.brokerCount;

        return Card(
          elevation: 0,
          color: HexaColors.brandPrimary.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: HexaColors.brandPrimary.withValues(alpha: 0.25),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20), // Increased internal padding to 20
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Purchases (${period.label})',
                      style: const TextStyle(
                        fontSize: 18, // Section Title: 18 Bold
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (suppliers > 0 || brokers > 0)
                      Text(
                        '$suppliers suppliers${brokers > 0 ? ' · $brokers brokers' : ''}',
                        style: const TextStyle(
                          fontSize: 12, // Subtitle: 12
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16), // Spacing: 16
                
                // Big Amount Value
                Text(
                  formatRupee(dash.totalPurchase),
                  style: TextStyle(
                    fontSize: 26, // Value: 26 Bold
                    fontWeight: FontWeight.bold,
                    color: HexaColors.brandPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                
                // Bills and quantities info
                Text(
                  '${dash.purchaseCount} bills total',
                  style: const TextStyle(
                    fontSize: 14, // Card Title/Subtitle: 14
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Quantities block (e.g. bags, KG, boxes, tins)
                HomeBoldMetricsLine(segments: unitSegments, fontSize: 16),
                const SizedBox(height: 16),
                
                // Status chips
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (received > 0) _metaChip('$received received', isReceived: true),
                    if (pending > 0) _metaChip('$pending pending delivery', isPending: true),
                  ],
                ),
                
                if (showProfit && dash.totalProfit.abs() > 0.01) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: HexaColors.profit.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Estimated Profit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${homeInr(dash.totalProfit)}'
                          '${dash.profitPercent != null ? ' (${dash.profitPercent!.toStringAsFixed(1)}%)' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: HexaColors.profit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  Widget _metaChip(String text, {bool isReceived = false, bool isPending = false}) {
    final chipColor = isReceived
        ? HexaColors.profit
        : (isPending ? const Color(0xFFEA580C) : const Color(0xFF64748B));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12, // Subtitle/Chip: 12
          color: chipColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
