import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/json_coerce.dart';

/// Dense timeline row for stock adjustment audit entries.
class StockTodayFeed extends StatelessWidget {
  const StockTodayFeed({
    super.key,
    required this.rows,
    this.maxRows,
    this.onItemTap,
    this.emptyMessage = 'No stock changes yet today',
  });

  final List<Map<String, dynamic>> rows;
  final int? maxRows;
  final void Function(String itemId)? onItemTap;
  final String emptyMessage;

  static String fmtQty(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return '$v';
  }

  static double _delta(Map<String, dynamic> r) {
    final n = coerceToDouble(r['new_qty']);
    final o = coerceToDouble(r['old_qty']);
    return n - o;
  }

  static ({IconData icon, Color color, String label}) _typeStyle(String? t) {
    switch (t) {
      case 'purchase':
        return (
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFFE65100),
          label: 'Purchase',
        );
      case 'verification':
        return (
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF2E7D32),
          label: 'Verified',
        );
      case 'damaged':
      case 'expired':
        return (
          icon: Icons.remove_circle_outline,
          color: const Color(0xFFC62828),
          label: 'Damage',
        );
      default:
        return (
          icon: Icons.tune_outlined,
          color: const Color(0xFF546E7A),
          label: 'Correction',
        );
    }
  }

  static String _timeLabel(dynamic raw) {
    final at = raw is String ? DateTime.tryParse(raw) : null;
    if (at == null) return '';
    return DateFormat.Hm().format(at.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final visible = maxRows == null ? rows : rows.take(maxRows!).toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(
          emptyMessage,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          _StockTodayFeedRow(
            row: visible[i],
            onTap: onItemTap,
          ),
          if (i < visible.length - 1)
            Divider(
              height: 1,
              indent: 52,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
        ],
      ],
    );
  }
}

class _StockTodayFeedRow extends StatelessWidget {
  const _StockTodayFeedRow({required this.row, this.onTap});

  final Map<String, dynamic> row;
  final void Function(String itemId)? onTap;

  @override
  Widget build(BuildContext context) {
    final style = StockTodayFeed._typeStyle(row['adjustment_type']?.toString());
    final delta = StockTodayFeed._delta(row);
    final unit = (row['unit'] ?? '').toString().trim();
    final deltaStr = delta >= 0
        ? '+${StockTodayFeed.fmtQty(delta.abs())}'
        : '-${StockTodayFeed.fmtQty(delta.abs())}';
    final deltaColor = delta > 0
        ? const Color(0xFF2E7D32)
        : delta < 0
            ? const Color(0xFFC62828)
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final name = row['item_name']?.toString() ?? 'Item';
    final itemId = row['item_id']?.toString();
    final who = row['updated_by_name']?.toString() ?? '—';
    final sub = '${style.label} · $who';

    return InkWell(
      onTap: itemId != null && itemId.isNotEmpty
          ? () {
              if (onTap != null) {
                onTap!(itemId);
              } else {
                context.push('/catalog/item/$itemId');
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, size: 18, color: style.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$deltaStr${unit.isNotEmpty ? ' $unit' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: deltaColor,
                  ),
                ),
                Text(
                  StockTodayFeed._timeLabel(row['updated_at']),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Source badge for item detail stock history rows.
class StockAdjustmentSourceBadge extends StatelessWidget {
  const StockAdjustmentSourceBadge({super.key, required this.adjustmentType});

  final String? adjustmentType;

  @override
  Widget build(BuildContext context) {
    final t = adjustmentType?.toLowerCase() ?? '';
    final (label, fg, bg) = switch (t) {
      'purchase' => ('PURCHASE', const Color(0xFFE65100), const Color(0xFFFFF3E0)),
      'verification' => ('VERIFIED', const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
      'damaged' || 'expired' => ('DAMAGE', const Color(0xFFC62828), const Color(0xFFFFEBEE)),
      _ => ('CORRECTION', const Color(0xFF546E7A), const Color(0xFFECEFF1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }
}
