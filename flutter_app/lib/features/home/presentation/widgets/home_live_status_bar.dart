import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/router/navigation_ext.dart';
import '../../../../core/providers/home_dashboard_provider.dart'
    show homeDashboardDataProvider, homeLowStockDetailFetchEnabledProvider;
import '../../../../core/providers/home_owner_dashboard_providers.dart'
    show
        homeLowStockAttentionCountProvider,
        homePendingDeliveryCountProvider,
        homeStaffReorderRequestCountProvider;
import '../../../../core/providers/notification_center_provider.dart'
    show homeWarehouseAlertsProvider, notificationCenterCoordinatorProvider;
import '../../../../core/providers/warehouse_alerts_provider.dart'
    show WarehouseAlerts;
import '../../../../core/theme/hexa_colors.dart';

/// Single-row operational status: sync, refresh time, alerts, deliveries.
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

    final syncColor = offline ? const Color(0xFFC62828) : HexaColors.profit;
    final syncLabel = offline ? 'Offline' : 'Synced';

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ref.read(homeLowStockDetailFetchEnabledProvider.notifier).state = true;
            ref.invalidate(homeDashboardDataProvider);
            ref.invalidate(notificationCenterCoordinatorProvider);
            _showHealthCenter(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // 1. Cloud Sync Status Icon & Label
                Icon(
                  offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                  size: 16,
                  color: syncColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cloud Sync Status',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Status Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: syncColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    syncLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: syncColor,
                    ),
                  ),
                ),

                const Spacer(),

                // 3. Retry Button
                TextButton.icon(
                  onPressed: () {
                    ref.read(homeLowStockDetailFetchEnabledProvider.notifier).state = true;
                    ref.invalidate(homeDashboardDataProvider);
                    ref.invalidate(notificationCenterCoordinatorProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text(
                    'Retry',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHealthCenter(BuildContext context) {
    showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: const _HomeStockStatusSheet(),
    );
  }
}

class _HomeStockStatusSheet extends ConsumerWidget {
  const _HomeStockStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(homeLowStockDetailFetchEnabledProvider.notifier).state = true;
    final attention = ref.watch(homeLowStockAttentionCountProvider);
    final pendingDel = ref.watch(homePendingDeliveryCountProvider);
    final reorderN = ref.watch(homeStaffReorderRequestCountProvider);
    final warehouse = ref.watch(homeWarehouseAlertsProvider) ??
        const WarehouseAlerts();
    final mismatchN = warehouse.pendingVerifications;
    final missingBarcode = warehouse.missingBarcode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
              children: [
                Expanded(
                  child: Text(
                    'Stock status',
                    style: HexaDsType.heading(18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Counts match Low stock page and delivery pipeline',
              style: HexaDsType.label(11, color: HexaDsColors.textMuted),
            ),
            const SizedBox(height: 12),
            _HealthTile(
              icon: Icons.warning_amber_rounded,
              label: 'Low stock · need attention',
              count: attention,
              color: const Color(0xFFDC2626),
              route: '/stock/low-stock',
            ),
            _HealthTile(
              icon: Icons.campaign_outlined,
              label: 'Staff reorder requests',
              count: reorderN,
              color: const Color(0xFF7C3AED),
              route: '/notifications',
            ),
            _HealthTile(
              icon: Icons.local_shipping_outlined,
              label: 'Pending delivery',
              count: pendingDel,
              color: const Color(0xFFEA580C),
              route: '/purchase?filter=pending_delivery',
              useTruck: true,
            ),
            _HealthTile(
              icon: Icons.qr_code_2_rounded,
              label: 'Missing barcode labels',
              count: missingBarcode,
              color: const Color(0xFF1565C0),
              route: '/stock/missing-barcodes',
            ),
            _HealthTile(
              icon: Icons.compare_arrows_rounded,
              label: 'Stock mismatch',
              count: mismatchN,
              color: const Color(0xFFB91C1C),
              route: '/reports',
            ),
          ],
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.route,
    this.useTruck = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final String route;
  final bool useTruck;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final accent = active ? color : const Color(0xFF94A3B8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? accent.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.of(context).pop();
            navigateActionRoute(context, route);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? accent.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    useTruck && active
                        ? Icons.local_shipping_rounded
                        : icon,
                    size: 22,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 36),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 999 ? '999+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
