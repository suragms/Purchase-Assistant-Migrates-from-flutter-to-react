import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../shared/widgets/operational_ui.dart';
import 'home_formatters.dart';

/// Grouped recent purchases + stock changes for the selected period.
class HomeRecentChangesSection extends ConsumerWidget {
  const HomeRecentChangesSection({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(homeRecentActivityFeedProvider);

    Widget wrapSection({required Widget child, Widget? trailing}) {
      if (embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            child,
          ],
        );
      }
      return OperationalSection(
        title: 'Recent changes',
        dense: true,
        trailing: trailing,
        child: child,
      );
    }

    return feedAsync.when(
      loading: () => wrapSection(
        child: const HomeSectionSkeleton(rows: 3),
      ),
      error: (_, __) => wrapSection(
        child: FriendlyLoadError(
          message: 'Could not load recent changes',
          onRetry: () => ref.invalidate(homeRecentActivityFeedProvider),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return wrapSection(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                'No recent warehouse activity',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
          );
        }
        final visible = items.take(5).toList();
        return wrapSection(
          trailing: TextButton(
            onPressed: () => context.go('/purchase'),
            child: const Text('See all', style: TextStyle(fontSize: 12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _RecentChangeRow(item: visible[i]),
                if (i < visible.length - 1)
                  const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

class _RecentChangeRow extends StatelessWidget {
  const _RecentChangeRow({required this.item});

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      'purchase' || 'purchase_added' || 'trade_purchase' =>
        Icons.shopping_cart_rounded,
      'stock' || 'stock_updated' || 'stock_change' || 'stock_adjustment' =>
        Icons.inventory_2_rounded,
      'usage' => Icons.trending_down_rounded,
      'transfer' => Icons.swap_horiz_rounded,
      'low_stock' || 'alert' || 'reorder' => Icons.warning_amber_rounded,
      'staff_login' || 'login' || 'user_active' => Icons.person_rounded,
      'barcode_scan' || 'scan' => Icons.qr_code_scanner_rounded,
      'item_created' || 'catalog' => Icons.add_box_rounded,
      _ => Icons.circle_outlined,
    };
    final color = switch (item.kind) {
      'purchase' => HexaColors.brandPrimary,
      'stock' => const Color(0xFF0D9488),
      'usage' => const Color(0xFFE65100),
      'transfer' => const Color(0xFF1565C0),
      _ => const Color(0xFF64748B),
    };
    final timeLabel = homeTimeAgo(item.at);
    final actor = item.actor?.trim();

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HexaDsType.listTitle(context).copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        [
          if (item.subtitle.isNotEmpty) item.subtitle,
          if (actor != null && actor.isNotEmpty) actor,
          timeLabel,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HexaDsType.bodySm(context).copyWith(fontSize: 11),
      ),
      trailing: item.amountInr != null && item.amountInr! > 0
          ? Text(
              homeInr(item.amountInr!),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: HexaColors.brandPrimary,
              ),
            )
          : (item.qtyChange != null && item.qtyChange!.isNotEmpty
              ? Text(
                  item.qtyChange!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF0D9488),
                  ),
                )
              : null),
      onTap: () {
        final id = item.routeId;
        if (id == null || id.isEmpty) return;
        if (item.kind == 'purchase') {
          context.push('/purchase/detail/$id');
        } else {
          context.push('/catalog/item/$id');
        }
      },
    );
  }
}

/// Shimmer placeholders for home feed sections.
class HomeSectionSkeleton extends StatelessWidget {
  const HomeSectionSkeleton({super.key, this.rows = 3});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: List.generate(
          rows,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
