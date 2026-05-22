import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'reports_bi_slice.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Compact legend rows under warehouse ring charts.
class BreakdownLegendList extends StatelessWidget {
  const BreakdownLegendList({
    super.key,
    required this.slices,
    this.selectedIndex,
    this.onTapIndex,
    this.maxRows = 8,
  });

  final List<ReportsBiSlice> slices;
  final int? selectedIndex;
  final ValueChanged<int>? onTapIndex;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No purchases in selected period.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    final show = slices.take(maxRows).toList();
    return Column(
      children: [
        for (var i = 0; i < show.length; i++)
          _LegendRow(
            slice: show[i],
            selected: selectedIndex == i,
            onTap: onTapIndex == null ? null : () => onTapIndex!(i),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.selected,
    this.onTap,
  });

  final ReportsBiSlice slice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trend = slice.pct >= 15
        ? Icons.trending_up_rounded
        : slice.pct <= 3
            ? Icons.trending_flat_rounded
            : Icons.trending_up_rounded;
    return Material(
      color: selected ? const Color(0xFFE8F5E0) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: slice.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (slice.subtitle.isNotEmpty)
                      Text(
                        slice.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inr0(slice.amount),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trend, size: 12, color: const Color(0xFF3B6D11)),
                      Text(
                        '${slice.pct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
