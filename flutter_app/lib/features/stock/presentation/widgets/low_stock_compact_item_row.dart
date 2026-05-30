import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/stock_providers.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import 'low_stock_category_tree.dart';

/// Dense single-row low-stock item (stock · reorder · bought · pending + icon actions).
class LowStockCompactItemRow extends ConsumerWidget {
  const LowStockCompactItemRow({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? '';
    final unitUp = unit.trim().isEmpty ? '' : unit.toUpperCase();
    final stock = coerceToDouble(item['current_stock']);
    final reorder = coerceToDouble(item['reorder_level']);
    final bought = coerceToDouble(item['period_purchased_qty']);
    final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
    final hasPending = item['has_pending_order'] == true;
    final pendingDelivery = lowStockItemPendingDelivery(item);
    final id = item['id']?.toString() ?? '';
    final onReorderList = item['reorder_entry_status']?.toString() == 'pending';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: id.isEmpty ? null : () => context.push('/catalog/item/$id'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 44,
                margin: const EdgeInsets.only(right: 8, top: 2),
                decoration: BoxDecoration(
                  color: stock <= 0
                      ? const Color(0xFFDC2626)
                      : HexaColors.warning,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        _MetricChip(
                          'Stock',
                          '${formatStockQtyNumber(stock)}${unitUp.isNotEmpty ? ' $unitUp' : ''}',
                        ),
                        _MetricChip(
                          'Reorder',
                          reorder > 0
                              ? formatStockQtyNumber(reorder)
                              : '—',
                        ),
                        if (bought > 0)
                          _MetricChip('Bought', formatStockQtyNumber(bought)),
                        if (pendingDel > 0.001 || hasPending)
                          _MetricChip(
                            'Pending',
                            pendingDel > 0.001
                                ? formatStockQtyNumber(pendingDel)
                                : 'Yes',
                            highlight: true,
                          ),
                        if (onReorderList)
                          const _MetricChip(
                            'Track',
                            'On list',
                            highlight: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onEditReorder != null)
                        _iconBtn(
                          tooltip: 'Set reorder level',
                          icon: Icons.tune_rounded,
                          onPressed: () => onEditReorder!(item),
                        ),
                      if (pendingDelivery && onReceive != null)
                        _iconBtn(
                          tooltip: 'Receive shipment',
                          icon: Icons.local_shipping_outlined,
                          onPressed: () => onReceive!(item),
                        )
                      else if (staffMode && onNotifyOwner != null)
                        _iconBtn(
                          tooltip: 'Inform owner',
                          icon: Icons.campaign_outlined,
                          color: HexaColors.brandPrimary,
                          onPressed: () => onNotifyOwner!(item),
                        )
                      else if (!staffMode && onOrderNow != null)
                        _iconBtn(
                          tooltip: 'Order now',
                          icon: Icons.add_shopping_cart_outlined,
                          color: HexaColors.brandPrimary,
                          onPressed: () => onOrderNow!(item),
                        ),
                      _iconBtn(
                        tooltip: 'Track purchase / reorder list',
                        icon: Icons.playlist_add_check_rounded,
                        onPressed: () => _trackPurchase(ref, context, item),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _trackPurchase(
    WidgetRef ref,
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final session = ref.read(sessionProvider);
    final id = item['id']?.toString() ?? '';
    if (session == null || id.isEmpty) return;
    try {
      await ref.read(hexaApiProvider).addItemToReorderList(
            businessId: session.primaryBusiness.id,
            itemId: id,
          );
      ref.invalidate(lowStockByCategoryProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added "${item['name']?.toString() ?? 'item'}" to reorder follow-up',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Widget _iconBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: color ?? const Color(0xFF64748B)),
      onPressed: onPressed,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: highlight ? const Color(0xFF0D9488) : const Color(0xFF64748B),
      ),
    );
  }
}
