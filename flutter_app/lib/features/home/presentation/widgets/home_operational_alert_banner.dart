import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/router/navigation_ext.dart';

/// Compact tappable alert strip (deliveries, low stock, verification).
class HomeOperationalAlertBanner extends ConsumerWidget {
  const HomeOperationalAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(homeOwnerPeriodDashboardProvider);
    final alerts = ref.watch(stockAlertCountsProvider).valueOrNull;
    final low = alerts?.low ?? 0;
    final crit = alerts?.critical ?? 0;
    final varianceN =
        ref.watch(stockVariancesTodayProvider).valueOrNull?.length ?? 0;
    final pending = dash.pendingDeliveryCount;

    String? title;
    String? subtitle;
    VoidCallback? onTap;

    if (pending > 0) {
      title = pending == 1
          ? '1 shipment awaiting delivery'
          : '$pending shipments awaiting delivery';
      subtitle = 'Tap to open Purchase history';
      onTap = () => navigateActionRoute(context, '/purchase?filter=pending_delivery');
    } else if (crit > 0) {
      title = crit == 1 ? '1 critical stock item' : '$crit critical stock items';
      subtitle = 'Tap to open low stock';
      onTap = () => pushLowStockDashboard(context);
    } else if (low > 0) {
      title = low == 1 ? '1 low stock item' : '$low low stock items';
      subtitle = 'Tap to open low stock';
      onTap = () => pushLowStockDashboard(context);
    } else if (varianceN > 0) {
      title = varianceN == 1
          ? '1 pending verification'
          : '$varianceN pending verifications';
      subtitle = 'Tap to review on Stock';
      onTap = () => navigateActionRoute(context, '/stock');
    }

    if (title == null) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFFFFF3E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFFFB74D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: Color(0xFFE65100),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: const Color(0xFF5D4037),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: HexaDsType.labelCaps(context).copyWith(
                          fontSize: 10,
                          color: const Color(0xFF8D6E63),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFE65100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
