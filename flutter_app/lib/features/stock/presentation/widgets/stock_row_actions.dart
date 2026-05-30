import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/utils/unit_utils.dart';
import '../quick_stock_action_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'stock_row_metrics.dart';
import 'stock_update_mode_toggle.dart';

Future<void> showStockRowActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final name = item['name']?.toString() ?? 'Item';
  final system = StockRowMetrics.systemQty(item);
  final physical = StockRowMetrics.physicalQty(item);
  final unit = StockRowMetrics.unit(item);
  final physLabel = physical == null
      ? 'Not counted'
      : '${formatStockQtyNumber(physical)} $unit';

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => HexaResponsiveSheetViewport(
      compact: true,
      bottomExtra: 12,
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
          const SizedBox(height: 6),
          Row(
            children: [
              _MetricChip(
                label: 'System',
                value: formatStockQtyNumber(system),
              ),
              const SizedBox(width: 8),
              _MetricChip(
                label: 'Physical',
                value: physLabel,
                muted: physical == null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _StockActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'Update physical stock',
            onTap: () async {
              Navigator.pop(ctx);
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
              Navigator.pop(ctx);
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
            label: 'View item activity',
            onTap: () {
              Navigator.pop(ctx);
              context.push('/catalog/item/$id');
            },
          ),
        ],
      ),
    ),
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: HexaDsType.label(10, color: HexaDsColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: muted ? HexaDsColors.textMuted : const Color(0xFF0F766E),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
