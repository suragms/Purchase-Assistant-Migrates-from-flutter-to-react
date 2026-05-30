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
            padding: const EdgeInsets.all(HexaOp.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Purchases (${period.label})',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: HexaColors.brandPrimary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                HomeBoldMetricsLine(segments: unitSegments, fontSize: 18),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatRupee(dash.totalPurchase),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: HomeMetricColors.amount,
                        ),
                      ),
                      TextSpan(
                        text: ' · ${dash.purchaseCount} bills',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HomeMetricColors.meta,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (received > 0) _metaChip('$received received'),
                    if (pending > 0) _metaChip('$pending pending delivery'),
                    if (suppliers > 0) _metaChip('$suppliers suppliers'),
                    if (brokers > 0) _metaChip('$brokers brokers'),
                  ],
                ),
                if (showProfit && dash.totalProfit.abs() > 0.01) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Profit ${homeInr(dash.totalProfit)}'
                    '${dash.profitPercent != null ? ' (${dash.profitPercent!.toStringAsFixed(1)}%)' : ''}',
                    style: HexaOp.caption(context).copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  Widget _metaChip(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
      );
}
