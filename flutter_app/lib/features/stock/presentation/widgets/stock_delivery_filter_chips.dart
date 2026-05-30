import 'package:flutter/material.dart';

import '../../../../core/providers/stock_providers.dart' show StockDeliveryFilter;

/// All / pending truck / delivered chips with live counts.
class StockDeliveryFilterChips extends StatelessWidget {
  const StockDeliveryFilterChips({
    super.key,
    required this.selected,
    required this.pendingCount,
    required this.deliveredCount,
    required this.onSelected,
  });

  final StockDeliveryFilter selected;
  final int pendingCount;
  final int deliveredCount;
  final ValueChanged<StockDeliveryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0 && deliveredCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _chip(
            label: 'All',
            selected: selected == StockDeliveryFilter.all,
            onTap: () => onSelected(StockDeliveryFilter.all),
          ),
          _chip(
            label: 'Pending truck',
            count: pendingCount,
            countColor: const Color(0xFFEA580C),
            icon: Icons.local_shipping_outlined,
            selected: selected == StockDeliveryFilter.pending,
            onTap: () => onSelected(StockDeliveryFilter.pending),
          ),
          _chip(
            label: 'Delivered',
            count: deliveredCount,
            countColor: const Color(0xFF16A34A),
            icon: Icons.check_circle_outline_rounded,
            selected: selected == StockDeliveryFilter.delivered,
            onTap: () => onSelected(StockDeliveryFilter.delivered),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int? count,
    Color? countColor,
    IconData? icon,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: countColor),
            const SizedBox(width: 4),
          ],
          Text(label, style: const TextStyle(fontSize: 11)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: countColor ?? const Color(0xFF64748B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 999 ? '999+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }
}
