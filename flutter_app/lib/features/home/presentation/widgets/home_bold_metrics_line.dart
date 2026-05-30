import 'package:flutter/material.dart';

/// Bold colored quantity tokens for owner home (bags · kg · boxes · tins).
class HomeBoldMetricsLine extends StatelessWidget {
  const HomeBoldMetricsLine({
    super.key,
    required this.segments,
    this.fontSize = 17,
  });

  final List<HomeBoldMetricSegment> segments;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return Text(
        'No data in this period',
        style: TextStyle(
          fontSize: fontSize - 3,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF94A3B8),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0)
            Text(
              '·',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFCBD5E1),
              ),
            ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: segments[i].value,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    color: segments[i].color,
                  ),
                ),
                if (segments[i].unit.isNotEmpty)
                  TextSpan(
                    text: ' ${segments[i].unit}',
                    style: TextStyle(
                      fontSize: fontSize - 2,
                      fontWeight: FontWeight.w700,
                      color: segments[i].color.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class HomeBoldMetricSegment {
  const HomeBoldMetricSegment({
    required this.value,
    required this.unit,
    required this.color,
  });

  final String value;
  final String unit;
  final Color color;
}

/// Shared palette for purchase vs warehouse metrics.
abstract final class HomeMetricColors {
  static const bags = Color(0xFF065F46);
  static const kg = Color(0xFF0D9488);
  static const boxes = Color(0xFFCA8A04);
  static const tins = Color(0xFF7C3AED);
  static const amount = Color(0xFF0F172A);
  static const meta = Color(0xFF64748B);
}
