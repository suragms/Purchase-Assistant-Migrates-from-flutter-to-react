import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/unit_utils.dart';
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: HomeSectionSkeleton(rows: 3),
        ),
      );
    }

    final dash = dashState.snapshot.data;
    {
        final unitParts = <String>[];
        if (dash.totalBags > 0.001) {
          unitParts.add('${_qty(dash.totalBags)} bags');
        }
        if (dash.totalKg > 0.001) {
          unitParts.add('${_qty(dash.totalKg)} KG');
        }
        if (dash.totalBoxes > 0.001) {
          unitParts.add('${_qty(dash.totalBoxes)} boxes');
        }
        if (dash.totalTins > 0.001) {
          unitParts.add('${_qty(dash.totalTins)} tins');
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
                const SizedBox(height: 8),
                if (unitParts.isNotEmpty)
                  Text(
                    unitParts.join(' · '),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      height: 1.2,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  '${formatRupee(dash.totalPurchase)} · ${dash.purchaseCount} bills',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
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
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _action(context, 'Add purchase', Icons.add_shopping_cart_rounded,
                          () => context.push('/purchase/new')),
                      _action(context, 'Pending', Icons.local_shipping_outlined,
                          () => context.go('/purchase')),
                      _action(context, 'Suppliers', Icons.store_outlined,
                          () => context.push('/contacts?tab=suppliers')),
                      _action(context, 'Brokers', Icons.handshake_outlined,
                          () => context.push('/contacts?tab=brokers')),
                      _action(context, 'History', Icons.receipt_long_outlined,
                          () => context.go('/purchase')),
                      _action(context, 'Reports', Icons.bar_chart_rounded,
                          () => context.go('/reports')),
                    ],
                  ),
                ),
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

  Widget _action(
      BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
