import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import 'low_stock_category_tree.dart';
import 'stock_row_metrics.dart';

/// Full item context — opened from compact low-stock row (tap or overflow).
Future<void> showLowStockItemDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  required bool staffMode,
  bool ownerInformed = false,
  void Function(Map<String, dynamic> item)? onOrderNow,
  void Function(Map<String, dynamic> item)? onNotifyOwner,
  void Function(Map<String, dynamic> item)? onEditReorder,
  void Function(Map<String, dynamic> item)? onStockUpdate,
  void Function(Map<String, dynamic> item)? onSystemStockUpdate,
  void Function(Map<String, dynamic> item)? onReceive,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _LowStockItemDetailSheet(
      item: item,
      staffMode: staffMode,
      ownerInformed: ownerInformed,
      onOrderNow: onOrderNow,
      onNotifyOwner: onNotifyOwner,
      onEditReorder: onEditReorder,
      onStockUpdate: onStockUpdate,
      onSystemStockUpdate: onSystemStockUpdate,
      onReceive: onReceive,
    ),
  );
}

class _LowStockItemDetailSheet extends StatelessWidget {
  const _LowStockItemDetailSheet({
    required this.item,
    required this.staffMode,
    required this.ownerInformed,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onSystemStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final bool ownerInformed;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onSystemStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  static const _critical = Color(0xFFDC2626);
  static const _warn = Color(0xFFF59E0B);
  static const _ok = Color(0xFF16A34A);
  static const _primaryBtn = Color(0xFF065F46);

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Item';
    final unit = StockRowMetrics.unit(item);
    final system = StockRowMetrics.systemQty(item);
    final physical = StockRowMetrics.physicalQty(item);
    final reorder = coerceToDouble(item['reorder_level']);
    final bought = coerceToDouble(item['period_purchased_qty']);
    final supplier = item['supplier_name']?.toString().trim() ?? '';
    final pendingDelivery = lowStockItemPendingDelivery(item);
    final out = system <= 0;

    final statusLabel = out
        ? 'OUT OF STOCK'
        : (reorder > 0 && system <= reorder)
            ? 'LOW STOCK'
            : 'NEEDS ATTENTION';
    final statusColor = out ? _critical : (system <= reorder ? _warn : _ok);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: statusColor,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Current stock',
            value: '${formatStockQtyNumber(system)} $unit',
          ),
          _DetailRow(
            label: 'Physical count',
            value: physical != null && physical.isFinite
                ? '${formatStockQtyNumber(physical)} $unit'
                : '—',
          ),
          _DetailRow(
            label: 'Reorder level',
            value: reorder > 0
                ? '${formatStockQtyNumber(reorder)} $unit'
                : 'Not set',
          ),
          if (bought > 0)
            _DetailRow(
              label: 'Last purchase (period)',
              value: '${formatStockQtyNumber(bought)} $unit',
            ),
          if (supplier.isNotEmpty)
            _DetailRow(label: 'Supplier', value: supplier),
          const SizedBox(height: 16),
          if (onStockUpdate != null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryBtn,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                Navigator.pop(context);
                onStockUpdate!(item);
              },
              child: const Text(
                'Update physical stock',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          if (onSystemStockUpdate != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: _primaryBtn,
                side: const BorderSide(color: _primaryBtn),
              ),
              onPressed: () {
                Navigator.pop(context);
                onSystemStockUpdate!(item);
              },
              child: const Text(
                'Update system stock',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (!staffMode && onOrderNow != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: _primaryBtn,
                side: const BorderSide(color: _primaryBtn),
              ),
              onPressed: () {
                Navigator.pop(context);
                onOrderNow!(item);
              },
              child: const Text(
                'Create purchase',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (staffMode && onNotifyOwner != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: ownerInformed
                  ? null
                  : () {
                      Navigator.pop(context);
                      onNotifyOwner!(item);
                    },
              child: Text(ownerInformed ? 'Owner informed' : 'Inform owner'),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onEditReorder != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onEditReorder!(item);
                  },
                  child: const Text('Set reorder level'),
                ),
              if (pendingDelivery && onReceive != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onReceive!(item);
                  },
                  child: const Text('Receive delivery'),
                ),
              TextButton(
                onPressed: () {
                  final id = item['id']?.toString();
                  Navigator.pop(context);
                  if (id != null && id.isNotEmpty) {
                    context.push('/catalog/item/$id');
                  }
                },
                child: const Text('Item profile'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: HexaColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
