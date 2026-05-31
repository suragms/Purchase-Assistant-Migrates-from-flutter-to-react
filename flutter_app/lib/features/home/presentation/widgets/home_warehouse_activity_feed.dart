import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../shared/widgets/hexa_empty_state.dart';
import '../../../../shared/widgets/operational_ui.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;
import 'home_warehouse_activity_row.dart';

/// Unified warehouse activity — collapsible on home (max 15 rows).
class HomeWarehouseActivityFeed extends ConsumerStatefulWidget {
  const HomeWarehouseActivityFeed({
    super.key,
    this.maxRows = 5,
  });

  final int maxRows;

  @override
  ConsumerState<HomeWarehouseActivityFeed> createState() =>
      _HomeWarehouseActivityFeedState();
}

class _HomeWarehouseActivityFeedState
    extends ConsumerState<HomeWarehouseActivityFeed> {
  bool _expanded = false;

  void _openFullPage() => context.push('/home/activity');

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(homePeriodProvider);
    final feedAsync = ref.watch(homeRecentActivityFeedProvider);
    final title = switch (period) {
      HomePeriod.today => 'Recent activity (today)',
      HomePeriod.week => 'Recent activity (week)',
      HomePeriod.month => 'Recent activity (month)',
      HomePeriod.year => 'Recent activity (year)',
      HomePeriod.allTime => 'Recent activity (all time)',
      HomePeriod.custom => 'Recent activity (custom range)',
    };

    return feedAsync.when(
      loading: () => OperationalSection(
        title: title,
        dense: true,
        child: const HomeSectionSkeleton(rows: 4),
      ),
      error: (_, __) => OperationalSection(
        title: title,
        dense: true,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber_rounded, size: 16),
          title: const Text(
            'Activity unavailable',
            style: TextStyle(fontSize: 13),
          ),
          trailing: TextButton(
            onPressed: () => ref.invalidate(homeRecentActivityFeedProvider),
            child: const Text('Retry'),
          ),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return OperationalSection(
            title: title,
            dense: true,
            child: HexaEmptyState(
              icon: Icons.history_rounded,
              title: 'No activity in this period',
              subtitle: 'Stock updates and purchases will appear here.',
            ),
          );
        }
        final cap = widget.maxRows.clamp(1, 15);
        final preview = items.take(cap).toList();
        final visible = _expanded ? items.take(15).toList() : preview;

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ListTile(
                title: Text(title, style: HexaOp.cardTitle(context)),
                subtitle: Text(
                  '${items.length} events in period',
                  style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _openFullPage,
                      child: const Text('View all', style: TextStyle(fontSize: 12)),
                    ),
                    if (items.length > cap)
                      IconButton(
                        icon: Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        onPressed: () =>
                            setState(() => _expanded = !_expanded),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (var i = 0; i < visible.length; i++) ...[
                WarehouseActivityCompactRow(item: visible[i]),
                if (i < visible.length - 1)
                  const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              if (!_expanded && items.length > cap)
                TextButton(
                  onPressed: _openFullPage,
                  child: Text('Show ${items.length - cap} more'),
                ),
            ],
          ),
        );
      },
    );
  }
}
