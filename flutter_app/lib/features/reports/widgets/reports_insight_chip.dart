import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';

class ReportsInsightChip extends StatelessWidget {
  const ReportsInsightChip({
    super.key,
    required this.label,
    this.trendUp,
    this.onTap,
  });

  final String label;
  final bool? trendUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = trendUp == null
        ? const Color(0xFF64748B)
        : (trendUp! ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsInsightChipRow extends StatelessWidget {
  const ReportsInsightChipRow({super.key, required this.chips});

  final List<ReportsInsightChip> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}
