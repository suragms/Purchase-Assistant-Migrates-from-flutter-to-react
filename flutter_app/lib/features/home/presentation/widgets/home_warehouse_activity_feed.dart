import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/operational_ui.dart';
import 'home_formatters.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;

/// Unified warehouse activity — collapsible on home (max 15 rows).
class HomeWarehouseActivityFeed extends ConsumerStatefulWidget {
  const HomeWarehouseActivityFeed({super.key});

  @override
  ConsumerState<HomeWarehouseActivityFeed> createState() =>
      _HomeWarehouseActivityFeedState();
}

class _HomeWarehouseActivityFeedState
    extends ConsumerState<HomeWarehouseActivityFeed> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(homePeriodProvider);
    final feedAsync = ref.watch(homeRecentActivityFeedProvider);
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final title = switch (period) {
      HomePeriod.today => 'Warehouse activity (today)',
      HomePeriod.week => 'Warehouse activity (week)',
      HomePeriod.month => 'Warehouse activity (month)',
      HomePeriod.year => 'Warehouse activity (year)',
      HomePeriod.allTime => 'Warehouse activity (all time)',
      HomePeriod.custom => 'Warehouse activity (custom range)',
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
            child: const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                'No activity in this period',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
          );
        }
        final preview = items.take(5).toList();
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
                      onPressed: () => context.push(
                        isStaff ? '/staff/activity' : '/staff/activity',
                      ),
                      child: const Text('View all', style: TextStyle(fontSize: 12)),
                    ),
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
                _ActivityRow(item: visible[i]),
                if (i < visible.length - 1)
                  const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              if (!_expanded && items.length > 5)
                TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  child: Text('Show ${items.length - 5} more'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      'purchase' || 'purchase_added' || 'trade_purchase' =>
        Icons.shopping_cart_rounded,
      'delivery_verified' => Icons.local_shipping_rounded,
      'stock_quick_purchase' => Icons.add_shopping_cart_rounded,
      'stock' ||
      'stock_updated' ||
      'stock_change' ||
      'stock_adjustment' ||
      'physical_count' =>
        Icons.inventory_2_rounded,
      'stock_correction' || 'correction' => Icons.build_rounded,
      'opening_stock' || 'opening_stock_set' => Icons.inventory_outlined,
      'reorder' || 'reorder_created' => Icons.shopping_bag_outlined,
      'low_stock' || 'alert' => Icons.warning_amber_rounded,
      _ => Icons.circle_outlined,
    };
    final color = switch (item.kind) {
      'purchase' || 'stock_quick_purchase' => HexaColors.brandPrimary,
      'delivery_verified' => HexaColors.profit,
      'stock' || 'physical_count' || 'stock_correction' || 'correction' =>
        const Color(0xFF0D9488),
      _ => const Color(0xFF64748B),
    };
    final actor = item.actor?.trim();
    final subtitle = <String>[
      item.subtitle,
      if (actor != null && actor.isNotEmpty) 'By $actor',
      homeTimeAgo(item.at),
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    );
  }
}
