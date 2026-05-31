import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import 'low_stock_category_tree.dart';

/// Expandable item tile with unit grid, stock progress, and role actions.
class LowStockItemDetailTile extends StatefulWidget {
  const LowStockItemDetailTile({
    super.key,
    required this.item,
    required this.staffMode,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  @override
  State<LowStockItemDetailTile> createState() => _LowStockItemDetailTileState();
}

class _LowStockItemDetailTileState extends State<LowStockItemDetailTile> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final name = item['name']?.toString() ?? '—';
    final physicalRaw = item['physical_stock_qty'];
    final physical = physicalRaw == null
        ? coerceToDouble(item['current_stock'])
        : coerceToDouble(physicalRaw);
    final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
    final pending = item['has_pending_order'] == true;
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? '';
    final unitUp = unit.trim().isEmpty ? '' : unit.toUpperCase();
    final id = item['id']?.toString() ?? '';
    final pendingDelivery = lowStockItemPendingDelivery(item);
    final showReceive = pending &&
        (item['last_purchase_delivered'] == false || pendingDel > 0.001);

    final primary = _RowPrimaryAction.resolve(
      pendingDelivery: pendingDelivery,
      showReceive: showReceive,
      hasPending: pending,
      staffMode: widget.staffMode,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: const Border(
            left: BorderSide(color: Color(0xFFDC2626), width: 3),
          ),
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: id.isEmpty ? null : () => context.push('/catalog/item/$id'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz_rounded),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Text('Open item'),
                          ),
                          if (widget.onEditReorder != null)
                            const PopupMenuItem(
                              value: 'reorder',
                              child: Text('Reorder level'),
                            ),
                          if (widget.onStockUpdate != null)
                            const PopupMenuItem(
                              value: 'stock',
                              child: Text('Stock update'),
                            ),
                          if (widget.staffMode && widget.onNotifyOwner != null)
                            const PopupMenuItem(
                              value: 'notify',
                              child: Text('Inform owner'),
                            ),
                        ],
                        onSelected: (v) {
                          switch (v) {
                            case 'open':
                              if (id.isNotEmpty) {
                                context.push('/catalog/item/$id');
                              }
                            case 'reorder':
                              widget.onEditReorder?.call(item);
                            case 'stock':
                              widget.onStockUpdate?.call(item);
                            case 'notify':
                              widget.onNotifyOwner?.call(item);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Physical ${formatStockQtyForUnit(unit, physical)}'
                    '${unitUp.isNotEmpty ? ' $unitUp' : ''}'
                    '${pendingDel > 0.001 ? ' · Pending ${formatStockQtyForUnit(unit, pendingDel)}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => _runPrimary(context, primary, item),
                      child: Text(primary.label),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _runPrimary(
    BuildContext context,
    _RowPrimaryAction primary,
    Map<String, dynamic> item,
  ) {
    switch (primary.kind) {
      case _PrimaryKind.verify:
      case _PrimaryKind.receive:
        widget.onReceive?.call(item);
      case _PrimaryKind.pending:
        break;
      case _PrimaryKind.order:
        if (widget.staffMode) {
          widget.onNotifyOwner?.call(item);
        } else {
          widget.onOrderNow?.call(item);
        }
    }
  }
}

enum _PrimaryKind { verify, receive, pending, order }

class _RowPrimaryAction {
  const _RowPrimaryAction({
    required this.kind,
    required this.label,
  });

  final _PrimaryKind kind;
  final String label;

  factory _RowPrimaryAction.resolve({
    required bool pendingDelivery,
    required bool showReceive,
    required bool hasPending,
    required bool staffMode,
  }) {
    if (pendingDelivery && showReceive) {
      return const _RowPrimaryAction(
        kind: _PrimaryKind.verify,
        label: 'Verify delivery',
      );
    }
    if (hasPending) {
      return const _RowPrimaryAction(
        kind: _PrimaryKind.pending,
        label: 'Pending order',
      );
    }
    return _RowPrimaryAction(
      kind: _PrimaryKind.order,
      label: staffMode ? 'Inform owner' : 'Order now',
    );
  }
}
