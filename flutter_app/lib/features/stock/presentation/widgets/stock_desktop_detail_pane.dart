import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';
import '../stock_compact_update_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'stock_row_metrics.dart';

/// Desktop right pane: selected item metrics + recent activity.
class StockDesktopDetailPane extends ConsumerWidget {
  const StockDesktopDetailPane({super.key, required this.item});

  final Map<String, dynamic>? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item == null) {
      return const Center(
        child: Text(
          'Select an item',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
      );
    }
    final id = item!['id']?.toString() ?? '';
    final name = item!['name']?.toString() ?? 'Item';
    final unit = StockRowMetrics.unit(item!);
    final purchased = StockRowMetrics.purchasedQty(item!);
    final stock = StockRowMetrics.stockQty(item!);
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
            'Purchase',
            purchased == null ? '—' : '${formatStockQtyNumber(purchased)} $unit',
          ),
          _metricRow('Stock', '${formatStockQtyNumber(stock)} $unit'),
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
                onPressed: () => showStockCompactUpdateSheet(
                  context: context,
                  ref: ref,
                  item: item!,
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Physical'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showStockQuickPurchaseSheet(
                  context: context,
                  ref: ref,
                  item: item!,
                ),
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text('Purchase'),
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
