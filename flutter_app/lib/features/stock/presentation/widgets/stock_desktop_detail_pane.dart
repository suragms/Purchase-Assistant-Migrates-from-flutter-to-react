import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';
import '../quick_stock_action_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'stock_row_metrics.dart';

/// Desktop right pane: selected item metrics + recent activity.
class StockDesktopDetailPane extends ConsumerWidget {
  const StockDesktopDetailPane({super.key, required this.item});

  final Map<String, dynamic>? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: HexaColors.brandPrimary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select an item',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose a row on the left to see stock metrics and recent activity.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
        ),
      );
    }
    final id = item!['id']?.toString() ?? '';
    final name = item!['name']?.toString() ?? 'Item';
    final unit = StockRowMetrics.unit(item!);
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final opening = StockRowMetrics.openingQty(item!);
    final purchased = StockRowMetrics.purchasedQty(item!);
    final pending = StockRowMetrics.pendingDeliveryQty(item!);
    final stock = StockRowMetrics.systemQty(item!);
    final physical = StockRowMetrics.physicalQty(item!);
    final diff = StockRowMetrics.diffQty(item!);
    final activityAsync = id.isEmpty
        ? const AsyncValue<Map<String, dynamic>>.data({})
        : ref.watch(stockItemActivityProvider(id));

    return ColoredBox(
      color: const Color(0xFFFAFAF8),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _metricRow(
            'Opening',
            opening == null ? '—' : '${formatStockQtyForUnit(unit, opening)} $unit',
          ),
          if (!isStaff)
            _metricRow(
              'Purchased',
              purchased == null
                  ? '—'
                  : '${formatStockQtyForUnit(unit, purchased)} $unit',
            ),
          _metricRow(
            'Pending',
            pending == null || pending < 0.001
                ? '—'
                : '${formatStockQtyForUnit(unit, pending)} $unit',
          ),
          _metricRow('System', '${formatStockQtyForUnit(unit, stock)} $unit'),
          _metricRow(
            'Physical',
            physical == null
                ? '—'
                : '${formatStockQtyForUnit(unit, physical)} $unit',
          ),
          _metricRow(
            'Difference',
            StockRowMetrics.signedDiffLine(diff, unit).replaceAll('\n', ' '),
            valueColor: StockRowMetrics.diffColor(diff),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showQuickStockActionSheet(
                  context: context,
                  ref: ref,
                  item: item!,
                ),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Verify physical'),
              ),
              if (!isStaff)
                FilledButton.tonalIcon(
                  onPressed: () => showStockQuickPurchaseSheet(
                    context: context,
                    ref: ref,
                    item: item!,
                  ),
                  icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                  label: const Text('New purchase'),
                ),
              if (!isStaff)
                OutlinedButton.icon(
                  onPressed: id.isEmpty
                      ? null
                      : () => context.push('/catalog/item/$id/edit'),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Set reorder'),
                ),
              OutlinedButton(
                onPressed:
                    id.isEmpty ? null : () => context.push('/catalog/item/$id'),
                child: const Text('Full detail'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Recent activity', style: HexaDsType.label(12)),
          const SizedBox(height: 8),
          activityAsync.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, __) => const Text(
              'Could not load activity',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            data: (data) {
              final events = (data['activity'] as List?) ?? [];
              if (events.isEmpty) {
                return const Text(
                  'No recent activity',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                );
              }
              return Column(
                children: [
                  for (final e in events.take(8))
                    if (e is Map)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e['title']?.toString() ??
                              e['kind']?.toString() ??
                              '—',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          e['actor_name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style:
                  HexaDsType.label(12).copyWith(color: const Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
