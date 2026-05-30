import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import 'low_stock_category_tree.dart';
import 'low_stock_item_detail_sheet.dart';
import 'stock_row_metrics.dart';

/// Mobile-first low-stock row (~90px): name · stock · status · 2 actions.
class LowStockCompactItemRow extends ConsumerWidget {
  const LowStockCompactItemRow({
    super.key,
    required this.item,
    required this.staffMode,
    this.hideSubcategory = false,
    this.ownerInformed = false,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
    this.onStockUpdate,
    this.onSystemStockUpdate,
    this.onReceive,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final bool hideSubcategory;
  final bool ownerInformed;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;
  final void Function(Map<String, dynamic> item)? onStockUpdate;
  final void Function(Map<String, dynamic> item)? onSystemStockUpdate;
  final void Function(Map<String, dynamic> item)? onReceive;

  static const _critical = Color(0xFFDC2626);
  static const _warn = Color(0xFFF59E0B);
  static const _primaryBtn = Color(0xFF065F46);
  static const _border = Color(0xFFE2E8E6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unit = StockRowMetrics.unit(item);
    final system = StockRowMetrics.systemQty(item);
    final reorder = coerceToDouble(item['reorder_level']);
    final out = system <= 0;
    final low = !out && reorder > 0 && system <= reorder;
    final pendingDelivery = lowStockItemPendingDelivery(item);

    final statusLabel = out
        ? 'OUT OF STOCK'
        : pendingDelivery
            ? 'PENDING DELIVERY'
            : low
                ? 'LOW STOCK'
                : 'NEEDS ATTENTION';
    final statusColor = out
        ? _critical
        : pendingDelivery
            ? _warn
            : low
                ? _warn
                : const Color(0xFF64748B);

    void openDetails() {
      showLowStockItemDetailSheet(
        context: context,
        ref: ref,
        item: item,
        staffMode: staffMode,
        ownerInformed: ownerInformed,
        onOrderNow: onOrderNow,
        onNotifyOwner: onNotifyOwner,
        onEditReorder: onEditReorder,
        onStockUpdate: onStockUpdate,
        onSystemStockUpdate: onSystemStockUpdate,
        onReceive: onReceive,
      );
    }

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: openDetails,
        onLongPress: openDetails,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88, maxHeight: 100),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _border, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (!hideSubcategory && sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      'Stock: ${formatStockQtyNumber(system)} $unit',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF334155),
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onStockUpdate != null)
                    _PrimaryAction(
                      label: '+ Stock',
                      filled: true,
                      onTap: () => onStockUpdate!(item),
                    ),
                  const SizedBox(height: 6),
                  if (!staffMode && onOrderNow != null)
                    _PrimaryAction(
                      label: 'Order',
                      filled: false,
                      onTap: () => onOrderNow!(item),
                    )
                  else if (staffMode && onNotifyOwner != null)
                    _PrimaryAction(
                      label: ownerInformed ? 'Informed' : 'Inform',
                      filled: false,
                      enabled: !ownerInformed,
                      onTap: () => onNotifyOwner!(item),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                color: const Color(0xFF64748B),
                onPressed: openDetails,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? LowStockCompactItemRow._primaryBtn : const Color(0xFF94A3B8);
    if (filled) {
      return SizedBox(
        width: 76,
        height: 36,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: enabled ? fg : const Color(0xFFE2E8E6),
            padding: EdgeInsets.zero,
            minimumSize: const Size(76, 36),
          ),
          onPressed: enabled ? onTap : null,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return SizedBox(
      width: 76,
      height: 36,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg.withValues(alpha: 0.5)),
          padding: EdgeInsets.zero,
          minimumSize: const Size(76, 36),
        ),
        onPressed: enabled ? onTap : null,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
