import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../stock_compact_update_sheet.dart';
import '../stock_quick_purchase_sheet.dart';

Future<void> showStockRowActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final name = item['name']?.toString() ?? 'Item';
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _StockActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'Update Physical Stock',
            onTap: () async {
              Navigator.pop(ctx);
              await showStockCompactUpdateSheet(
                context: context,
                ref: ref,
                item: item,
              );
            },
          ),
          _StockActionTile(
            icon: Icons.add_shopping_cart_outlined,
            label: 'Add Purchase Quantity',
            onTap: () async {
              Navigator.pop(ctx);
              await showStockQuickPurchaseSheet(
                context: context,
                ref: ref,
                item: item,
              );
            },
          ),
          _StockActionTile(
            icon: Icons.info_outline_rounded,
            label: 'View Item Activity',
            onTap: () {
              Navigator.pop(ctx);
              context.push('/catalog/item/$id');
            },
          ),
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
