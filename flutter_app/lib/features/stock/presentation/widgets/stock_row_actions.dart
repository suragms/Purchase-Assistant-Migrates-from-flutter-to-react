import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../catalog/presentation/widgets/item_stock_metric_strip.dart';
import '../quick_stock_action_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'stock_row_metrics.dart';
import 'stock_update_mode_toggle.dart';

Future<void> showStockRowActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  VoidCallback? onBeforeNavigate,
  VoidCallback? onAfterNavigateReturn,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final name = item['name']?.toString() ?? 'Item';
  final system = StockRowMetrics.systemQty(item);
  final unit = StockRowMetrics.unit(item);

  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stock in hand · ${formatStockQtyForUnit(unit, system)}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(height: 8),
        ItemStockMetricStrip(stock: item),
        const SizedBox(height: 6),
        _StockActionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Update physical stock',
          onTap: () async {
            Navigator.pop(context);
            await showQuickStockActionSheet(
              context: context,
              ref: ref,
              item: item,
              initialMode: StockUpdateMode.physical,
            );
          },
        ),
        _StockActionTile(
          icon: Icons.memory_outlined,
          label: 'Update system stock',
          onTap: () async {
            Navigator.pop(context);
            await showQuickStockActionSheet(
              context: context,
              ref: ref,
              item: item,
              initialMode: StockUpdateMode.system,
            );
          },
        ),
        _StockActionTile(
          icon: Icons.add_shopping_cart_outlined,
          label: 'Add purchase quantity',
          onTap: () async {
            Navigator.pop(context);
            await showStockQuickPurchaseSheet(
              context: context,
              ref: ref,
              item: item,
            );
          },
        ),
        _StockActionTile(
          icon: Icons.info_outline_rounded,
          label: 'View item activity',
          onTap: () async {
            Navigator.pop(context);
            onBeforeNavigate?.call();
            await context.push('/catalog/item/$id');
            onAfterNavigateReturn?.call();
          },
        ),
      ],
    ),
  );
}

class _StockActionTile extends StatelessWidget {
  const _StockActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 22, color: const Color(0xFF0F766E)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
