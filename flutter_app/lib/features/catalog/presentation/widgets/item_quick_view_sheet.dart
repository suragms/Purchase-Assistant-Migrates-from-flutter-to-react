import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';
import 'item_stock_metric_strip.dart';
import '../../../stock/presentation/quick_stock_action_sheet.dart';

/// Compact item preview from stock row tap.
Future<void> showItemQuickView({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
}) async {
  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: _ItemQuickViewBody(
      itemId: itemId,
      itemName: itemName,
      parentRef: ref,
    ),
  );
}

class _ItemQuickViewBody extends ConsumerWidget {
  const _ItemQuickViewBody({
    required this.itemId,
    required this.itemName,
    required this.parentRef,
  });

  final String itemId;
  final String itemName;
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockItemDetailProvider(itemId));

    return stockAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: ListSkeleton(rowCount: 3),
      ),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load stock',
        onRetry: () => ref.invalidate(stockItemDetailProvider(itemId)),
      ),
      data: (stock) {
        final unit = (stock['stock_unit'] ?? stock['unit'] ?? 'bag').toString();
        final cur = coerceToDouble(stock['current_stock']);
        final reorder = coerceToDouble(stock['reorder_level']);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Full page',
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/catalog/item/$itemId');
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            Text(
              'Stock in hand · ${formatStockQtyForUnit(unit, cur)}${isKgStockUnit(unit) ? ' ${unit.toUpperCase()}' : ''}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 8),
            ItemStockMetricStrip(stock: stock),
            if (reorder > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Reorder at ${formatStockQtyForUnit(unit, reorder)}',
                style: HexaDsType.body(11, color: HexaDsColors.textMuted),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await showQuickStockActionSheet(
                  context: context,
                  ref: parentRef,
                  item: stock,
                );
              },
              child: const Text('Update stock'),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/catalog/item/$itemId');
              },
              child: const Text('Open item page'),
            ),
          ],
        );
      },
    );
  }
}
