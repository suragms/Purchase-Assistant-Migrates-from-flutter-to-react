import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../stock_compact_update_sheet.dart';
import '../stock_quick_purchase_sheet.dart';
import 'stock_row_metrics.dart';
import 'stock_status_badge.dart';
import 'stock_table_layout.dart';

/// Warehouse operational row: ITEM | PURCHASE | STOCK | DIFF + quick actions.
class StockWarehouseRow extends StatelessWidget {
  const StockWarehouseRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.ref,
    this.isStaffMode = true,
    this.isFirstRow = false,
    this.isSelected = false,
    this.onSelect,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final WidgetRef ref;
  final bool isStaffMode;
  final bool isFirstRow;
  final bool isSelected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final codeRaw = item['item_code']?.toString().trim() ?? '';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unit = StockRowMetrics.unit(item);
    final purchased = StockRowMetrics.purchasedQty(item);
    final stock = StockRowMetrics.stockQty(item);
    final diff = StockRowMetrics.diffQty(item);
    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final updatedAt = item['last_stock_updated_at']?.toString();
    final updatedBy = item['last_stock_updated_by']?.toString();
    final relative = formatStockRelativeTime(updatedAt);
    final isLowOrCritical = status == 'low' || status == 'critical';

    final metaParts = <String>[
      if (codeRaw.isNotEmpty) '#$codeRaw',
      if (relative.isNotEmpty) relative,
      if (!isStaffMode && updatedBy != null && updatedBy.isNotEmpty) updatedBy,
    ];

    final itemId = item['id']?.toString() ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HexaResponsive.pageGutter(context, operational: true),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: StockTableLayout.rowMinHeight,
            ),
            decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow)
                .copyWith(
              color: isSelected ? const Color(0xFFEFF6FF) : StockTableLayout.rowFill,
              border: isLowOrCritical
                  ? const Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 3),
                    )
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        StockTableLayout.cellHPadding,
                        6,
                        4,
                        6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          if (sub.isNotEmpty &&
                              sub.toLowerCase() != name.trim().toLowerCase())
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HexaDsType.label(11).copyWith(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          if (metaParts.isNotEmpty)
                            Text(
                              metaParts.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HexaDsType.label(11).copyWith(
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _metricCell(
                    StockRowMetrics.qtyLine(purchased, unit),
                    const Color(0xFF1A1A1A),
                  ),
                  _stockCell(stock, unit),
                  _metricCell(
                    StockRowMetrics.signedDiffLine(diff, unit),
                    StockRowMetrics.diffColor(diff),
                    bold: true,
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width >= 340
                        ? StockTableLayout.actionsWidth
                        : 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (MediaQuery.sizeOf(context).width >= 340) ...[
                          _actionIcon(
                            context,
                            Icons.inventory_2_outlined,
                            'Physical stock',
                            () => showStockCompactUpdateSheet(
                              context: context,
                              ref: ref,
                              item: item,
                            ),
                          ),
                          _actionIcon(
                            context,
                            Icons.add_shopping_cart_outlined,
                            'Purchase qty',
                            () => showStockQuickPurchaseSheet(
                              context: context,
                              ref: ref,
                              item: item,
                            ),
                          ),
                          _actionIcon(
                            context,
                            Icons.info_outline_rounded,
                            'Item detail',
                            () {
                              if (itemId.isEmpty) return;
                              if (onSelect != null) {
                                onSelect!();
                              } else {
                                context.push('/catalog/item/$itemId');
                              }
                            },
                          ),
                        ],
                      ],
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

  Widget _stockCell(double stock, String unit) {
    final statusLabel = StockRowMetrics.inlineStatusLabel(item);
    final statusColor = StockRowMetrics.inlineStatusColor(item);
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatStockQtyNumber(stock),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
          Text(
            unit,
            maxLines: 1,
            style: HexaDsType.label(9).copyWith(
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
          Text(
            statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HexaDsType.label(9).copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCell(String text, Color color, {bool bold = false}) {
    final lines = text.split('\n');
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            lines.first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (lines.length > 1)
            Text(
              lines[1],
              maxLines: 1,
              style: HexaDsType.label(9).copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionIcon(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: 26,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 48),
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
