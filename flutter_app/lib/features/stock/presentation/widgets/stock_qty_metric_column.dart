import 'package:flutter/material.dart';

import '../../../../core/utils/unit_utils.dart';

/// Compact Purch / Stock / Moved numbers (no unit suffix) for dense rows.
class StockQtyMetricColumn extends StatelessWidget {
  const StockQtyMetricColumn({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.muted = false,
    this.showLabel = true,
  });

  final String label;
  final double value;
  final bool highlight;
  final bool muted;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final show = value.abs() > 0.0001 || label == 'Stock';
    final text = show ? formatStockQtyNumber(value) : '—';
    final color = highlight
        ? const Color(0xFFE65100)
        : muted
            ? Colors.black38
            : Colors.black87;
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel) ...[
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.black38,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three metric columns: purchased, current, moved (variance).
class StockQtyMetricTriple extends StatelessWidget {
  const StockQtyMetricTriple({
    super.key,
    required this.purchased,
    required this.current,
    required this.moved,
    this.highlightCurrent = false,
    this.currentSubtitle,
    this.showColumnLabels = true,
  });

  final double purchased;
  final double current;
  final double moved;

  /// Low / critical / out styling on current qty.
  final bool highlightCurrent;
  final String? currentSubtitle;
  final bool showColumnLabels;

  @override
  Widget build(BuildContext context) {
    final labels = showColumnLabels;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StockQtyMetricColumn(
          label: 'Purchased',
          value: purchased,
          muted: purchased <= 0,
          showLabel: labels,
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StockQtyMetricColumn(
              label: 'Stock',
              value: current,
              highlight: highlightCurrent,
              showLabel: labels,
            ),
            if (currentSubtitle != null && currentSubtitle!.isNotEmpty)
              SizedBox(
                width: 44,
                child: Text(
                  currentSubtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: Colors.black38),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
        StockQtyMetricColumn(
          label: 'Diff',
          value: moved,
          muted: moved == 0,
          highlight: moved.abs() > 0.0001,
          showLabel: labels,
        ),
      ],
    );
  }
}
