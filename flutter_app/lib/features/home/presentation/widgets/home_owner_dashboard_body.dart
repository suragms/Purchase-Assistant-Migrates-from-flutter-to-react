import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart'
    show lowStockByCategoryProvider;
import '../../../stock/presentation/widgets/low_stock_category_tree.dart'
    show countLowStockForTab, LowStockTreeTab;
import 'home_owner_compact_alerts.dart';
import 'home_owner_quick_actions.dart';
import 'home_purchase_control_center.dart';
import 'home_warehouse_activity_feed.dart';
import 'home_warehouse_snapshot_card.dart';

/// Owner dashboard: alerts → purchases → warehouse → tools → recent activity.
class HomeOwnerDashboardBody extends ConsumerWidget {
  const HomeOwnerDashboardBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = HexaResponsive.sectionGap(context);
    final lowCount = ref.watch(lowStockByCategoryProvider).maybeWhen(
          data: (g) => countLowStockForTab(g, LowStockTreeTab.allLow),
          orElse: () => 0,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeOwnerCompactAlerts(),
        SizedBox(height: gap),
        const HomePurchaseControlCenter(),
        SizedBox(height: gap),
        const HomeWarehouseSnapshotCard(),
        SizedBox(height: gap),
        HomeOwnerQuickActions(
          lowStockCount: lowCount,
          onPurchase: () => context.push('/purchase/new'),
          onStock: () => context.go('/stock'),
          onLowStock: () => context.push('/stock/low-stock'),
          onDelivered: () => context.go('/purchase?filter=received'),
          onReports: () => context.go('/reports'),
          onUsers: () => context.push('/settings/users'),
          onBarcode: () => context.push('/barcode/bulk-print'),
          onReorder: () => context.push('/stock/reorder'),
        ),
        SizedBox(height: gap),
        const HomeWarehouseActivityFeed(),
      ],
    );
  }
}
