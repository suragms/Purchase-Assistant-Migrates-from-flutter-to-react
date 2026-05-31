import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../filters/reports_filter_sheet.dart';
import '../reports_bi_tab.dart';
import 'reports_layout.dart';

/// Desktop 3-column analytics layout: nav / content / filters.
class ReportsDesktopScaffold extends ConsumerWidget {
  const ReportsDesktopScaffold({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onMore,
    required this.body,
  });

  final ReportsBiTab selectedTab;
  final void Function(ReportsBiTab tab) onTabSelected;
  final VoidCallback onMore;
  final Widget body;

  static const _navWidth = 220.0;
  static const _filterWidth = 320.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _navWidth,
          child: Material(
            color: const Color(0xFFF8FAFC),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final t in ReportsBiTabX.primaryRow)
                  ListTile(
                    dense: true,
                    selected: selectedTab == t,
                    title: Text(
                      t.shortLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => onTabSelected(t),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  title: const Text('More reports…',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: onMore,
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
        const VerticalDivider(width: 1),
        const SizedBox(
          width: _filterWidth,
          child: ReportsFilterDrawer(),
        ),
      ],
    );
  }
}

/// Tablet 2-column master-detail placeholder — detail pane shows body.
class ReportsTabletScaffold extends StatelessWidget {
  const ReportsTabletScaffold({
    super.key,
    required this.list,
    required this.detail,
  });

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 4, child: list),
        const VerticalDivider(width: 1),
        Expanded(flex: 6, child: detail),
      ],
    );
  }
}
