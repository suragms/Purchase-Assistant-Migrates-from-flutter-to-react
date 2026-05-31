import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/analytics_kpi_provider.dart';
import '../../../../core/providers/app_period_provider.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Quick period chips + range label for Reports (aligned with Home period).
class ReportsPeriodBar extends ConsumerWidget {
  const ReportsPeriodBar({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onCustomRange,
    required this.onSyncHome,
    this.compact = false,
  });

  final String selectedPreset;
  final void Function(String preset) onPresetSelected;
  final VoidCallback onCustomRange;
  final VoidCallback onSyncHome;
  final bool compact;

  static const presets = ['Today', 'Week', 'Month', 'Quarter', 'Year'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';
    final homeLabel = ref.watch(appSelectedPeriodProvider).label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      p,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    selected: selectedPreset == p,
                    onSelected: (_) => onPresetSelected(p),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ChoiceChip(
                label: Text(
                  'Custom',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                selected: selectedPreset == 'Custom',
                onSelected: (_) => onCustomRange(),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                rangeFmt,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  color: HexaColors.brandPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: onSyncHome,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Match Home · $homeLabel',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
