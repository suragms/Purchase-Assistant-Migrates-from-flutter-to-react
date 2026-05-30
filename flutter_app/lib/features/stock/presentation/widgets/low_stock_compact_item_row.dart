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
import 'stock_row_metrics.dart';

/// Dense low-stock row: bold metric tiles + labeled action chips.
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
  final void Function(Map<String, dynamic> item)? onReceive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unitUp = StockRowMetrics.unit(item);
    final system = StockRowMetrics.systemQty(item);
    final physical = StockRowMetrics.physicalQty(item);
    final reorder = coerceToDouble(item['reorder_level']);
    final bought = coerceToDouble(item['period_purchased_qty']);
    final pendingDel = coerceToDoubleNullable(item['pending_delivery_qty']) ?? 0;
    final hasPending = item['has_pending_order'] == true;
    final pendingDelivery = lowStockItemPendingDelivery(item);
    final id = item['id']?.toString() ?? '';
    final onReorderList = item['reorder_entry_status']?.toString() == 'pending';
    final out = system <= 0;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: id.isEmpty ? null : () => context.push('/catalog/item/$id'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 44,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: out
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.15,
                          ),
                        ),
                        if (!hideSubcategory && sub.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (ownerInformed)
                        const _LifecyclePill(
                          label: 'Informed',
                          color: Color(0xFF16A34A),
                          icon: Icons.check_circle_rounded,
                        ),
                      if (out)
                        const _LifecyclePill(
                          label: 'Out',
                          color: Color(0xFFDC2626),
                          icon: Icons.remove_shopping_cart_rounded,
                        ),
                      if (pendingDelivery)
                        const _LifecyclePill(
                          label: 'Delivery',
                          color: Color(0xFFEA580C),
                          icon: Icons.local_shipping_outlined,
                        )
                      else if (hasPending || pendingDel > 0.001)
                        const _LifecyclePill(
                          label: 'Pending',
                          color: Color(0xFFEA580C),
                          icon: Icons.schedule_rounded,
                        ),
                      if (bought > 0)
                        _LifecyclePill(
                          label: 'Bought ${formatStockQtyNumber(bought)}',
                          color: const Color(0xFF2563EB),
                          icon: Icons.shopping_bag_outlined,
                        ),
                      if (onReorderList)
                        const _LifecyclePill(
                          label: 'On list',
                          color: Color(0xFF0D9488),
                          icon: Icons.playlist_add_check_rounded,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _MetricTile(
                      label: 'System',
                      value: formatStockQtyNumber(system),
                      unit: unitUp,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 6),
                    _MetricTile(
                      label: 'Physical',
                      value: physical != null && physical.isFinite
                          ? formatStockQtyNumber(physical)
                          : '—',
                      unit: physical != null && physical.isFinite ? unitUp : '',
                      color: const Color(0xFF0D9488),
                    ),
                    const SizedBox(width: 6),
                    _MetricTile(
                      label: 'Reorder',
                      value: reorder > 0 ? formatStockQtyNumber(reorder) : '—',
                      unit: reorder > 0 ? unitUp : '',
                      color: const Color(0xFFEA580C),
                    ),
                    const SizedBox(width: 6),
                    _MetricTile(
                      label: 'Purchased',
                      value: bought > 0 ? formatStockQtyNumber(bought) : '—',
                      unit: bought > 0 ? unitUp : '',
                      color: const Color(0xFF7C3AED),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (staffMode && onNotifyOwner != null)
                    _ActionChip(
                      icon: ownerInformed
                          ? Icons.check_rounded
                          : Icons.campaign_rounded,
                      label: ownerInformed ? 'Informed' : 'Inform owner',
                      color: ownerInformed
                          ? const Color(0xFF16A34A)
                          : HexaColors.brandPrimary,
                      onTap: ownerInformed ? null : () => onNotifyOwner!(item),
                    )
                  else if (!staffMode && onOrderNow != null)
                    _ActionChip(
                      icon: Icons.add_shopping_cart_rounded,
                      label: 'Order',
                      color: HexaColors.brandPrimary,
                      onTap: () => onOrderNow!(item),
                    ),
                  if (pendingDelivery && onReceive != null)
                    _ActionChip(
                      icon: Icons.local_shipping_rounded,
                      label: 'Receive',
                      color: const Color(0xFFEA580C),
                      onTap: () => onReceive!(item),
                    ),
                  if (onEditReorder != null)
                    _ActionChip(
                      icon: Icons.tune_rounded,
                      label: 'Reorder lvl',
                      color: const Color(0xFF64748B),
                      onTap: () => onEditReorder!(item),
                    ),
                  if (onStockUpdate != null)
                    _ActionChip(
                      icon: Icons.inventory_2_outlined,
                      label: 'Update stock',
                      color: const Color(0xFF1565C0),
                      onTap: () => onStockUpdate!(item),
                    ),
                  _ActionChip(
                    icon: Icons.playlist_add_check_rounded,
                    label: 'Track',
                    color: const Color(0xFF0D9488),
                    onTap: () => _trackPurchase(ref, context, item),
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
}

class _LifecyclePill extends StatelessWidget {
  const _LifecyclePill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled ? color : const Color(0xFF94A3B8);
    return Material(
      color: fg.withValues(alpha: enabled ? 0.12 : 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
