import 'package:flutter/material.dart';

import 'stock_row_metrics.dart';

/// Orange / green truck badge for pending vs delivered purchase lines.
class StockDeliveryTruckBadge extends StatelessWidget {
  const StockDeliveryTruckBadge({
    super.key,
    required this.item,
    this.compact = false,
  });

  final Map<String, dynamic> item;
  final bool compact;

  static const _pendingColor = Color(0xFFEA580C);
  static const _deliveredColor = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final kind = StockRowMetrics.deliveryIndicator(item);
    if (kind == StockDeliveryIndicator.none) return const SizedBox.shrink();

    final isPending = kind == StockDeliveryIndicator.pending;
    final color = isPending ? _pendingColor : _deliveredColor;
    final qty = isPending ? StockRowMetrics.deliveryQtyBadge(item) : '';
    final size = compact ? 16.0 : 18.0;

    return Tooltip(
      message: isPending ? 'Pending delivery' : 'Delivered to stock',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 5,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPending
                  ? Icons.local_shipping_outlined
                  : Icons.local_shipping_rounded,
              size: size,
              color: color,
            ),
            if (isPending && qty.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                qty,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
            ] else if (!isPending) ...[
              const SizedBox(width: 2),
              Icon(Icons.check_rounded, size: size - 2, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
