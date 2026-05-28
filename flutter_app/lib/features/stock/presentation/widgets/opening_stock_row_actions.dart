import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/stock_providers.dart';
import 'opening_stock_set_sheet.dart';

Future<void> showOpeningStockRowActions({
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
          _ActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'Set Opening Stock',
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showOpeningStockSetSheet(
                context: context,
                ref: ref,
                item: item,
              );
              if (ok == true && context.mounted) {
                ref.invalidate(openingStockSetupProvider);
              }
            },
          ),
          _ActionTile(
            icon: Icons.info_outline_rounded,
            label: 'View Item Detail',
            onTap: () {
              Navigator.pop(ctx);
              context.push('/catalog/item/$id');
            },
          ),
          _ActionTile(
            icon: Icons.history_rounded,
            label: 'View Activity',
            onTap: () {
              Navigator.pop(ctx);
              context.push('/stock/$id/history?name=${Uri.encodeComponent(name)}');
            },
          ),
          _ActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'View Ledger',
            onTap: () {
              Navigator.pop(ctx);
              context.push('/catalog/item/$id/ledger');
            },
          ),
          ],
        ),
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
    );
  }
}

