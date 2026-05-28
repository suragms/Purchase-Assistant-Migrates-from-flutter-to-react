import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/notifications_provider.dart'
    show mergedNotificationFeedProvider;
import '../../../../core/providers/stock_providers.dart'
    show openingStockMissingProvider;
import '../../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../../core/theme/hexa_colors.dart';

/// Priority alert cards (2-column grid); hidden when all counts are zero.
class HomeCriticalAlertsGrid extends ConsumerWidget {
  const HomeCriticalAlertsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;
    final feed = ref.watch(mergedNotificationFeedProvider);
    final unread = feed.where((n) => !n.isRead).toList();

    var pendingDel = 0;
    var lowTotal = 0;
    var openingN = 0;
    var variances = 0;
    var exportFail = 0;
    var syncFail = 0;

    for (final n in unread) {
      final kind = n.serverKind ?? '';
      if (n.id == 'wh_pending_delivery' ||
          kind == 'delivery_pending' ||
          n.title.toLowerCase().contains('pending deliver')) {
        pendingDel++;
        continue;
      }
      if (n.id == 'wh_low_stock' || kind == 'low_stock') {
        lowTotal++;
        continue;
      }
      if (n.id == 'wh_opening_stock' || kind == 'opening_stock_pending') {
        openingN++;
        continue;
      }
      if (kind == 'stock_variance' || kind == 'stock_mismatch') {
        variances++;
        continue;
      }
      if (kind == 'export_failed') {
        exportFail++;
        continue;
      }
      if (kind == 'sync_failed') {
        syncFail++;
      }
    }

    if (pendingDel == 0 && dash.pendingDeliveryCount > 0) {
      pendingDel = dash.pendingDeliveryCount;
    }
    if (openingN == 0) {
      final opening = ref.watch(openingStockMissingProvider).valueOrNull;
      openingN = (opening?['missing_count'] as num?)?.toInt() ?? 0;
    }

    final cards = <_AlertCardSpec>[];
    if (pendingDel > 0) {
      cards.add(_AlertCardSpec(
        title: 'Pending delivery',
        count: pendingDel,
        subtitle: 'Purchases awaiting receipt',
        color: HexaColors.profit,
        onTap: () => context.push(
          isStaff ? '/staff/receive' : '/purchase',
        ),
        actionLabel: isStaff ? 'Receive' : 'View bills',
      ));
    }
    if (lowTotal > 0) {
      cards.add(_AlertCardSpec(
        title: 'Low stock',
        count: lowTotal,
        subtitle: 'Items below reorder level',
        color: HexaColors.warning,
        onTap: () => context.push('/stock/low-stock'),
        actionLabel: 'Open stock',
      ));
    }
    if (openingN > 0) {
      cards.add(_AlertCardSpec(
        title: 'Opening stock',
        count: openingN,
        subtitle: 'Items need initial stock',
        color: HexaColors.warning,
        onTap: () => context.push('/stock/opening-setup'),
        actionLabel: 'Set up',
      ));
    }
    if (variances > 0) {
      cards.add(_AlertCardSpec(
        title: 'Stock mismatch',
        count: variances,
        subtitle: 'Physical count differs from system',
        color: const Color(0xFFA32D2D),
        onTap: () => context.go('/reports'),
        actionLabel: 'Review',
      ));
    }
    if (exportFail > 0) {
      cards.add(_AlertCardSpec(
        title: 'Export failed',
        count: exportFail,
        subtitle: 'PDF or share errors',
        color: const Color(0xFFA32D2D),
        onTap: () => context.push('/notifications'),
        actionLabel: 'View',
      ));
    }
    if (syncFail > 0) {
      cards.add(_AlertCardSpec(
        title: 'Sync issue',
        count: syncFail,
        subtitle: 'Data may be stale',
        color: const Color(0xFFA32D2D),
        onTap: () => context.push('/notifications'),
        actionLabel: 'View',
      ));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    final visible = cards.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Critical alerts', style: HexaOp.cardTitle(context)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final card in visible)
                  SizedBox(
                    width: w.clamp(140, double.infinity),
                    child: _AlertCard(spec: card),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AlertCardSpec {
  const _AlertCardSpec({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.actionLabel,
  });

  final String title;
  final int count;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String actionLabel;
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.spec});

  final _AlertCardSpec spec;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: spec.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: spec.color.withValues(alpha: 0.45), width: 2),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: spec.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${spec.count}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: spec.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                spec.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: spec.onTap,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(spec.actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
