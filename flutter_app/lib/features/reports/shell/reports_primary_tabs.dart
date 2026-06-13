import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
import '../reports_bi_tab.dart';

/// Scrollable tab chips — avoids SegmentedButton label wrap/overlap on narrow screens.
class ReportsPrimaryTabs extends StatelessWidget {
  const ReportsPrimaryTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ReportsBiTab selected;
  final ValueChanged<ReportsBiTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        children: [
          for (final t in ReportsBiTabX.primaryTabs) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  t.shortLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected == t
                        ? HexaColors.brandPrimary
                        : const Color(0xFF64748B),
                  ),
                ),
                selected: selected == t,
                showCheckmark: true,
                checkmarkColor: HexaColors.brandPrimary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: (_) => onSelected(t),
                selectedColor: HexaColors.brandPrimary.withValues(alpha: 0.14),
                backgroundColor: HexaColors.brandCard,
                side: BorderSide(
                  color: selected == t
                      ? HexaColors.brandPrimary.withValues(alpha: 0.35)
                      : HexaColors.brandPrimary.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
