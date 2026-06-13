import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/analytics_kpi_provider.dart';
import '../../../../core/providers/app_period_provider.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Icon-only period toggles — fits in the Reports app bar under search.
class ReportsPeriodIconRow extends ConsumerWidget {
  const ReportsPeriodIconRow({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onCustomRange,
    this.onSyncHome,
    this.showRangeLabel = true,
  });

  final String selectedPreset;
  final void Function(String preset) onPresetSelected;
  final VoidCallback onCustomRange;
  final VoidCallback? onSyncHome;
  final bool showRangeLabel;

  static const presets = ['Today', 'Week', 'Month', 'Quarter', 'Year'];

  static const _icons = <String, IconData>{
    'Today': Icons.today_outlined,
    'Week': Icons.view_week_outlined,
    'Month': Icons.calendar_month_outlined,
    'Quarter': Icons.filter_3_outlined,
    'Year': Icons.date_range_outlined,
    'Custom': Icons.edit_calendar_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';
    final homeLabel = ref.watch(appSelectedPeriodProvider).label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final p in presets) ...[
              _PeriodIconButton(
                tooltip: p,
                icon: _icons[p] ?? Icons.circle_outlined,
                selected: selectedPreset == p,
                onTap: () => onPresetSelected(p),
              ),
            ],
            _PeriodIconButton(
              tooltip: 'Custom range',
              icon: _icons['Custom']!,
              selected: selectedPreset == 'Custom',
              onTap: onCustomRange,
            ),
          ],
        ),
        if (showRangeLabel) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeFmt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ),
              if (onSyncHome != null)
                TextButton(
                  onPressed: onSyncHome,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Match Home · $homeLabel',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PeriodIconButton extends StatelessWidget {
  const _PeriodIconButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? HexaColors.brandPrimary.withValues(alpha: 0.14)
              : HexaColors.brandCard,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 34,
              height: 32,
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? HexaColors.brandPrimary
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Legacy full chip row (desktop sidebar still uses list tiles).
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ReportsPeriodIconRow(
        selectedPreset: selectedPreset,
        onPresetSelected: onPresetSelected,
        onCustomRange: onCustomRange,
        onSyncHome: onSyncHome,
      ),
    );
  }
}
