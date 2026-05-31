import 'package:flutter/material.dart';

import '../reports_bi_tab.dart';
import '../presentation/widgets/reports_period_bar.dart';

/// Sticky period chips + segmented tab row for Reports shell.
class ReportsStickyChrome extends StatelessWidget {
  const ReportsStickyChrome({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onCustomRange,
    required this.onSyncHome,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onMore,
    this.compact = true,
  });

  final String selectedPreset;
  final void Function(String preset) onPresetSelected;
  final VoidCallback onCustomRange;
  final VoidCallback onSyncHome;
  final ReportsBiTab selectedTab;
  final void Function(ReportsBiTab tab) onTabSelected;
  final VoidCallback onMore;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final moreSelected =
        ReportsBiTabX.moreSheet.contains(selectedTab) ? selectedTab : null;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: ReportsPeriodBar(
              selectedPreset: selectedPreset,
              onPresetSelected: onPresetSelected,
              onCustomRange: onCustomRange,
              onSyncHome: onSyncHome,
              compact: compact,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final t in ReportsBiTabX.primaryRow)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                t.shortLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: selectedTab == t
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFF334155),
                                ),
                              ),
                              selected: selectedTab == t,
                              onSelected: (_) => onTabSelected(t),
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ActionChip(
                    label: Text(
                      moreSelected?.shortLabel ?? 'More',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    avatar: moreSelected != null
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Color(0xFF0F766E))
                        : null,
                    onPressed: onMore,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReportsStickyChromeDelegate extends SliverPersistentHeaderDelegate {
  ReportsStickyChromeDelegate({
    required this.selectedPreset,
    required this.onPresetSelected,
    required this.onCustomRange,
    required this.onSyncHome,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onMore,
  });

  final String selectedPreset;
  final void Function(String preset) onPresetSelected;
  final VoidCallback onCustomRange;
  final VoidCallback onSyncHome;
  final ReportsBiTab selectedTab;
  final void Function(ReportsBiTab tab) onTabSelected;
  final VoidCallback onMore;

  @override
  double get minExtent => 96;

  @override
  double get maxExtent => 96;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ReportsStickyChrome(
      selectedPreset: selectedPreset,
      onPresetSelected: onPresetSelected,
      onCustomRange: onCustomRange,
      onSyncHome: onSyncHome,
      selectedTab: selectedTab,
      onTabSelected: onTabSelected,
      onMore: onMore,
    );
  }

  @override
  bool shouldRebuild(covariant ReportsStickyChromeDelegate oldDelegate) {
    return oldDelegate.selectedPreset != selectedPreset ||
        oldDelegate.selectedTab != selectedTab;
  }
}
