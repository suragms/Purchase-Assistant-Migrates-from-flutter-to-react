import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';

/// Two-row compact circular quick actions (4 columns for owner).
class HomeQuickActionsGrid extends StatelessWidget {
  const HomeQuickActionsGrid({
    super.key,
    required this.isOwner,
    required this.onScan,
    required this.onStock,
    required this.onPurchase,
    required this.onReports,
    required this.onPrint,
    this.onDaily,
    required this.onUsers,
  });

  final bool isOwner;
  final VoidCallback onScan;
  final VoidCallback onStock;
  final VoidCallback onPurchase;
  final VoidCallback onReports;
  final VoidCallback onPrint;
  final VoidCallback? onDaily;
  final VoidCallback onUsers;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionSpec>[
      _QuickActionSpec(
        label: 'Scan',
        icon: Icons.qr_code_scanner_rounded,
        color: const Color(0xFF1B5E20),
        onTap: onScan,
      ),
      _QuickActionSpec(
        label: 'Stock',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF1565C0),
        onTap: onStock,
      ),
      _QuickActionSpec(
        label: 'Purchase',
        icon: Icons.add_shopping_cart_outlined,
        color: HexaColors.brandPrimary,
        onTap: onPurchase,
      ),
      _QuickActionSpec(
        label: 'Reports',
        icon: Icons.bar_chart_outlined,
        color: const Color(0xFF0D9488),
        onTap: onReports,
      ),
      _QuickActionSpec(
        label: 'Print',
        icon: Icons.print_outlined,
        color: const Color(0xFF455A64),
        onTap: onPrint,
      ),
      if (isOwner && onDaily != null)
        _QuickActionSpec(
          label: 'Daily',
          icon: Icons.summarize_outlined,
          color: const Color(0xFF5D4037),
          onTap: onDaily!,
        ),
      if (isOwner)
        _QuickActionSpec(
          label: 'Users',
          icon: Icons.group_outlined,
          color: const Color(0xFF6A1B9A),
          onTap: onUsers,
        ),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1.05,
      children: [
        for (final a in actions)
          _CompactCircularAction(
            icon: a.icon,
            label: a.label,
            color: a.color,
            onTap: a.onTap,
          ),
      ],
    );
  }
}

class _QuickActionSpec {
  const _QuickActionSpec({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _CompactCircularAction extends StatelessWidget {
  const _CompactCircularAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
