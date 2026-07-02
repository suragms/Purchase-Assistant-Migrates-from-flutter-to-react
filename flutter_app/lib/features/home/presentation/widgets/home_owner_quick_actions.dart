import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/widgets/hexa_count_badge.dart';

/// Owner dashboard quick actions (2×4 grid, ~56dp tiles).
class HomeOwnerQuickActions extends StatelessWidget {
  const HomeOwnerQuickActions({
    super.key,
    required this.onStock,
    required this.onPurchase,
    required this.onLowStock,
    required this.onDelivered,
    required this.onReports,
    required this.onUsers,
    required this.onBarcode,
    required this.onReorder,
    required this.onDailyLog,
    this.lowStockCount = 0,
  });

  final VoidCallback onStock;
  final VoidCallback onPurchase;
  final VoidCallback onLowStock;
  final VoidCallback onDelivered;
  final VoidCallback onReports;
  final VoidCallback onUsers;
  final VoidCallback onBarcode;
  final VoidCallback onReorder;
  final VoidCallback onDailyLog;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _Spec('Purchase', Icons.add_shopping_cart_rounded, HexaColors.brandPrimary, onPurchase),
      _Spec('Stock', Icons.inventory_2_rounded, const Color(0xFF1565C0), onStock),
      _Spec('Low stock', Icons.warning_amber_rounded, HexaColors.warning, onLowStock, badge: lowStockCount),
      _Spec('Deliveries', Icons.local_shipping_outlined, const Color(0xFFE65100), onDelivered),
      _Spec('Reports', Icons.bar_chart_rounded, const Color(0xFF0D9488), onReports),
      _Spec('Users', Icons.group_rounded, const Color(0xFF5D4037), onUsers),
      _Spec('Scan', Icons.qr_code_scanner_rounded, const Color(0xFF455A64), onBarcode),
      _Spec('Reorder', Icons.autorenew_rounded, const Color(0xFF7C3AED), onReorder),
      _Spec('Daily log', Icons.history_rounded, const Color(0xFF0D9488), onDailyLog),
    ];

    final width = MediaQuery.sizeOf(context).width;
    final cols = width < 360 ? 2 : 4;
    const double spacing = 8.0;
    final double gutter = HexaResponsive.pageGutter(context, operational: true);
    
    final double itemWidth = (width - (gutter * 2) - ((cols - 1) * spacing)) / cols;
    final childAspectRatio = itemWidth / 72.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tools',
          style: TextStyle(
            fontSize: 18, // Section Titles: 18 Bold
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: childAspectRatio,
          children: [
            for (final a in actions) _Tile(spec: a),
          ],
        ),
      ],
    );
  }
}

class _Spec {
  const _Spec(this.label, this.icon, this.color, this.onTap, {this.badge});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.spec});
  final _Spec spec;

  @override
  Widget build(BuildContext context) {
    final badge = spec.badge;
    return Material(
      color: spec.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: spec.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HexaCountBadge(
                count: badge,
                maxDisplay: 999,
                child: Icon(spec.icon, color: spec.color, size: 20),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  spec.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: spec.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
