import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/warehouse_alerts_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'home_formatters.dart';

/// Single-row operational status: sync, refresh time, alerts, staff, variances.
class HomeLiveStatusBar extends ConsumerWidget {
  const HomeLiveStatusBar({
    super.key,
    required this.offline,
    required this.lastRefreshedAt,
    this.isOwner = true,
  });

  final bool offline;
  final DateTime? lastRefreshedAt;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOwner) return const SizedBox.shrink();

    final alerts = ref.watch(stockAlertCountsProvider).valueOrNull;
    final low = alerts?.low ?? 0;
    final crit = alerts?.critical ?? 0;
    final warehouse = ref.watch(warehouseAlertsProvider).valueOrNull;
    final deliveryN = warehouse?.pendingDeliveries ?? 0;
    final mismatchN =
        warehouse?.pendingVerifications ??
        ref.watch(stockVariancesTodayProvider).valueOrNull?.length ??
        0;
    final ago = homeRefreshAgo(lastRefreshedAt);

    final statusLine = offline
        ? 'OFFLINE • Showing cached data • Last synced $ago'
        : 'LIVE • Updated $ago • $low low stock • $deliveryN pending delivery'
            '${crit > 0 ? ' • $crit critical' : ''}'
            '${mismatchN > 0 ? ' • $mismatchN stock mismatch' : ''}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showHealthCenter(context, warehouse),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                size: 16,
                color: offline ? const Color(0xFFC62828) : HexaColors.profit,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.bodySm(context).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HexaDsColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showHealthCenter(BuildContext context, WarehouseAlerts? a) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final alerts = a ?? const WarehouseAlerts();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Stock status',
                  style: HexaDsType.heading(18),
                ),
                const SizedBox(height: 8),
                _healthTile(
                  ctx,
                  icon: Icons.inventory_2_outlined,
                  label: 'Low stock items',
                  value: '${alerts.lowStock + alerts.criticalStock}',
                  route: '/stock',
                ),
                _healthTile(
                  ctx,
                  icon: Icons.local_shipping_outlined,
                  label: 'Pending delivery',
                  value: '${alerts.pendingDeliveries}',
                  route: '/purchase',
                ),
                _healthTile(
                  ctx,
                  icon: Icons.qr_code_2_rounded,
                  label: 'Missing barcode labels',
                  value: '${alerts.missingBarcode}',
                  route: '/stock/missing-barcodes',
                ),
                _healthTile(
                  ctx,
                  icon: Icons.compare_arrows_rounded,
                  label: 'Stock mismatch',
                  value: '${alerts.pendingVerifications}',
                  route: '/reports',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _healthTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String route,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      onTap: () {
        Navigator.of(context).pop();
        context.go(route);
      },
    );
  }
}
