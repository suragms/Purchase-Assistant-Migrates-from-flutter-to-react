import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/navigation_ext.dart';
import '../../../../core/router/shell_navigation.dart';
import '../../../../features/shell/shell_branch_provider.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/delivery_pipeline_provider.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart'
    show openingStockMissingProvider, stockStatusCountsProvider;
import 'home_analytics_helpers.dart';
import 'home_delivery_pipeline_card.dart';
import 'home_owner_quick_actions.dart';
import 'home_purchase_control_center.dart';
import 'home_warehouse_activity_feed.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;
import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';

/// Owner dashboard: alert strip → KPI grid → purchases → activity (compact).
class HomeOwnerDashboardBody extends ConsumerWidget {
  const HomeOwnerDashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = HexaResponsive.sectionGap(context);
    final dashState = ref.watch(homeDashboardDataProvider);
    if (dashState.refreshing &&
        dashState.snapshot.data == HomeDashboardData.empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(HexaOp.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const HomeSectionSkeleton(rows: 4),
                  const SizedBox(height: 8),
                  Text(
                    'Loading dashboard…',
                    style: HexaOp.caption(context),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final status = ref.watch(stockStatusCountsProvider).valueOrNull ?? const {};
    final low = coerceToInt(status['low']) + coerceToInt(status['critical']);
    final out = coerceToInt(status['out']);
    final openingN =
        coerceToInt(ref.watch(openingStockMissingProvider).valueOrNull?['missing_count']);
    final pipeline = ref.watch(deliveryPipelineProvider).valueOrNull;
    var pending = deliveryPipelinePendingCount(pipeline);
    if (pending == 0) {
      pending = dashState.snapshot.data.pendingDeliveryCount;
    }
    final dash = dashState.snapshot.data;
    final sh = dash.stockInHand;
    final HomeInventorySummary? invSummary = sh != null
        ? HomeInventorySummary(
            totalValueInr: sh.totalValueInr,
            bags: sh.bags,
            boxes: sh.boxes,
            tins: sh.tins,
            kg: sh.kg,
            itemCount: sh.itemCount,
          )
        : ref.watch(homeInventorySummaryProvider).valueOrNull;
    final lowCount = low + out;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (low > 0)
                _AlertChip(
                  label: 'Low stock · $low',
                  color: const Color(0xFFF59E0B),
                  onTap: () => pushLowStockDashboard(context),
                ),
              if (pending > 0) ...[
                if (low > 0) const SizedBox(width: 8),
                _AlertChip(
                  label: 'Pending delivery · $pending',
                  color: const Color(0xFFDC2626),
                  filled: true,
                  onTap: () => context.go('/purchase?filter=pending_delivery'),
                ),
              ],
              if (openingN > 0) ...[
                if (low > 0 || pending > 0) const SizedBox(width: 8),
                _AlertChip(
                  label: 'Opening stock · $openingN',
                  color: const Color(0xFFCA8A04),
                  onTap: () => pushOpeningStockSetup(context),
                ),
              ],
              if (out > 0) ...[
                if (low > 0 || pending > 0 || openingN > 0)
                  const SizedBox(width: 8),
                _AlertChip(
                  label: 'Out of stock · $out',
                  color: const Color(0xFFDC2626),
                  onTap: () => goShellTab(
                        context,
                        ref,
                        branch: ShellBranch.stock,
                        location: '/stock?status=out',
                      ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: gap),
        GridView.count(
          crossAxisCount: context.isDesktopLayout ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: context.isDesktopLayout
              ? 2.2
              : math.max(1.35, MediaQuery.sizeOf(context).width / 200),
          children: [
            _KpiTile(
              label: 'Purchases',
              value: '${dash.purchaseCount}',
              subtitle: dash.period.label,
              onTap: () => context.go('/purchase'),
            ),
            _KpiTile(
              label: 'Pending delivery',
              value: '$pending',
              subtitle: pending > 0 ? 'Needs action' : 'Clear',
              accent: pending > 0 ? const Color(0xFFDC2626) : null,
              onTap: () => context.go('/purchase?filter=pending_delivery'),
            ),
            _KpiTile(
              label: 'Low stock',
              value: '$lowCount',
              subtitle: 'Items below reorder',
              onTap: () => pushLowStockDashboard(context),
            ),
            _KpiTile(
              label: 'Warehouse',
              value: invSummary != null &&
                      inventoryUnitsLine(invSummary).isNotEmpty
                  ? inventoryUnitsLine(invSummary)
                  : '${invSummary?.itemCount ?? dash.itemSlices.length}',
              subtitle: invSummary != null &&
                      inventoryUnitsLine(invSummary).isNotEmpty
                  ? '${invSummary.itemCount} items on hand'
                  : 'Active items',
              onTap: () => goShellTab(
                    context,
                    ref,
                    branch: ShellBranch.stock,
                    location: '/stock',
                  ),
            ),
          ],
        ),
        SizedBox(height: gap),
        const HomeDeliveryPipelineCard(),
        SizedBox(height: gap),
        const HomePurchaseControlCenter(),
        SizedBox(height: gap),
        HomeOwnerQuickActions(
          lowStockCount: lowCount,
          onPurchase: () => pushPurchaseNew(context),
          onStock: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.stock,
                location: '/stock',
              ),
          onLowStock: () => pushLowStockDashboard(context),
          onDelivered: () => context.go('/purchase?filter=delivery_commit'),
          onReports: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.reports,
                location: '/reports',
              ),
          onUsers: () => context.push('/settings/users'),
          onBarcode: () => pushBarcodeScan(context),
          onReorder: () => pushStockReorder(context),
          onDailyLog: () => goShellTab(
                context,
                ref,
                branch: ShellBranch.home,
                location: '/home/activity',
              ),
        ),
        SizedBox(height: gap),
        const HomeWarehouseActivityFeed(maxRows: 3),
      ],
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.onTap,
    this.accent,
  });

  final String label;
  final String value;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 96,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                ),
                const SizedBox(height: 4),
                if (value.contains(' · '))
                  WarehouseUnitsSubtitleText(
                    subtitle: value,
                    fontSize: 13,
                    fallbackStyle: HexaDsType.metricPrimary(color: accent),
                  )
                else
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.metricPrimary(color: accent),
                  ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
