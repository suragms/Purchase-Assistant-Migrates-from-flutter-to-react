import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';

enum LowStockTreeTab { allLow, pendingOrder, outOfStock }

/// Expandable category → subcategory → item list for low-stock dashboards.
class LowStockCategoryTree extends StatefulWidget {
  const LowStockCategoryTree({
    super.key,
    required this.grouped,
    required this.tab,
    this.searchQuery = '',
    this.staffMode = false,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
  });

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped;
  final LowStockTreeTab tab;
  final String searchQuery;
  final bool staffMode;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;

  @override
  State<LowStockCategoryTree> createState() => _LowStockCategoryTreeState();
}

class _LowStockCategoryTreeState extends State<LowStockCategoryTree> {
  final _expandedCats = <String>{};

  bool _matchesTab(Map<String, dynamic> item) {
    final status = (item['stock_status']?.toString() ?? '').toLowerCase();
    final stock = coerceToDouble(item['current_stock']);
    final pending = item['has_pending_order'] == true;
    return switch (widget.tab) {
      LowStockTreeTab.pendingOrder => pending,
      LowStockTreeTab.outOfStock => stock <= 0 || status == 'out',
      LowStockTreeTab.allLow =>
        status == 'low' || status == 'critical' || (stock > 0 && status != 'out'),
    };
  }

  bool _matchesSearch(Map<String, dynamic> item) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      item['name'],
      item['category_name'],
      item['subcategory_name'],
      item['item_code'],
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final catEntry in widget.grouped.entries) {
      final subMap = <String, List<Map<String, dynamic>>>{};
      for (final subEntry in catEntry.value.entries) {
        final items = subEntry.value
            .where((it) => _matchesTab(it) && _matchesSearch(it))
            .toList();
        if (items.isNotEmpty) subMap[subEntry.key] = items;
      }
      if (subMap.isNotEmpty) filtered[catEntry.key] = subMap;
    }

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No items in this view', style: TextStyle(color: Colors.black54)),
        ),
      );
    }

    final cats = filtered.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: cats.length,
      itemBuilder: (ctx, ci) {
        final cat = cats[ci];
        final subMap = filtered[cat]!;
        final catCount =
            subMap.values.fold<int>(0, (n, list) => n + list.length);
        final expanded = _expandedCats.contains(cat);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  cat,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$catCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedCats.remove(cat);
                  } else {
                    _expandedCats.add(cat);
                  }
                }),
              ),
              if (expanded)
                for (final subEntry in subMap.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            subEntry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        Text(
                          '${subEntry.value.length}',
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final item in subEntry.value)
                    _LowStockItemRow(
                      item: item,
                      staffMode: widget.staffMode,
                      onOrderNow: widget.onOrderNow,
                      onNotifyOwner: widget.onNotifyOwner,
                      onEditReorder: widget.onEditReorder,
                    ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _LowStockItemRow extends StatelessWidget {
  const _LowStockItemRow({
    required this.item,
    required this.staffMode,
    this.onOrderNow,
    this.onNotifyOwner,
    this.onEditReorder,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final void Function(Map<String, dynamic> item)? onOrderNow;
  final void Function(Map<String, dynamic> item)? onNotifyOwner;
  final void Function(Map<String, dynamic> item)? onEditReorder;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final cur = coerceToDouble(item['current_stock']);
    final reorder = coerceToDouble(item['reorder_level']);
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? '';
    final status = stockDisplayStatusFromApi(item['stock_status']?.toString());
    final pending = item['has_pending_order'] == true;
    final pendingDays = (item['pending_order_days'] as num?)?.toInt();
    final supplier = item['supplier_name']?.toString().trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: const Border(left: BorderSide(color: Color(0xFFDC2626), width: 3)),
          color: const Color(0xFFFFF5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 4),
              StockNumberDisplay(
                qty: cur,
                unit: unit,
                status: status,
                hasPendingOrder: pending,
                pendingDays: pendingDays,
                fontSize: 16,
              ),
              Text(
                'Reorder: ${formatStockQtyNumber(reorder)} · Stock: ${formatStockQtyNumber(cur)} $unit'
                    .trim(),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              if (supplier.isNotEmpty)
                Text(
                  'Supplier: $supplier',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              if (pending)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.local_shipping_rounded, size: 16),
                    label: Text(
                      pendingDays != null
                          ? 'Ordered · $pendingDays d ago'
                          : 'Ordered · pending',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              if (!pending && !staffMode && onOrderNow != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onOrderNow!(item),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('Order now'),
                  ),
                ),
              ],
              if (staffMode) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (onEditReorder != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => onEditReorder!(item),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Reorder level'),
                      ),
                    if (onNotifyOwner != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => onNotifyOwner!(item),
                        icon: const Icon(Icons.notifications_active_outlined, size: 18),
                        label: const Text('Notify owner'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
