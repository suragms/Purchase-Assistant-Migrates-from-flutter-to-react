import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';

/// Dense operational row for slow / dead stock lists.
class SlowMovingRow extends StatelessWidget {
  const SlowMovingRow({
    super.key,
    required this.item,
    this.deadStyle = false,
  });

  final Map<String, dynamic> item;
  final bool deadStyle;

  @override
  Widget build(BuildContext context) {
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? '—';
    final unit = item['unit']?.toString() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final used = coerceToDouble(item['used_7d']);
    final idle = item['idle_days'] is int
        ? item['idle_days'] as int
        : int.tryParse('${item['idle_days']}') ?? 999;
    final bucket = item['aging_bucket']?.toString() ?? '';
    final insight = _insightText(item['insight_key']?.toString(), idle);

    Color badgeBg = const Color(0xFFE8F5E0);
    Color badgeFg = const Color(0xFF3B6D11);
    String badgeLabel = 'Active';
    if (deadStyle || bucket == '60d') {
      badgeBg = const Color(0xFFFFEBEE);
      badgeFg = const Color(0xFFA32D2D);
      badgeLabel = '60d idle';
    } else if (bucket == '30d') {
      badgeBg = const Color(0xFFFFF3E0);
      badgeFg = const Color(0xFFBA7517);
      badgeLabel = '30d idle';
    } else if (bucket == '15d') {
      badgeBg = const Color(0xFFFFF3E0);
      badgeFg = const Color(0xFFE65100);
      badgeLabel = '15d idle';
    } else if (bucket == '7d' || idle >= 7) {
      badgeBg = const Color(0xFFFFF8E1);
      badgeFg = const Color(0xFFBA7517);
      badgeLabel = '7d idle';
    }

    final lastMove = idle >= 999
        ? 'No recent movement'
        : idle == 0
            ? 'Moved today'
            : 'Last movement: $idle days ago';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: id.isEmpty
            ? null
            : () => context.push('/stock/intelligence/$id'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Current stock: ${stockDisplayPrimary(cur, unit)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    Text(
                      lastMove,
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    Text(
                      'Used (7d): ${stockDisplayPrimary(used, unit)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                    ),
                    if (insight.isNotEmpty)
                      Text(
                        insight,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: deadStyle
                              ? const Color(0xFFA32D2D)
                              : const Color(0xFFBA7517),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _insightText(String? key, int idleDays) {
    return switch (key) {
      'dead_stock_risk' => 'Dead stock risk — review before reordering.',
      'high_stock_low_usage' => 'High stock but low usage.',
      'slowing' when idleDays >= 21 =>
        'No movement for $idleDays days.',
      'slowing' => 'Movement is slowing.',
      'out_of_stock' => 'Out of stock.',
      _ => '',
    };
  }
}
