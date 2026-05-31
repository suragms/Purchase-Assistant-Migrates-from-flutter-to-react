import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_row_metrics.dart';
import 'stock_table_layout.dart';

/// Warehouse operational row — ITEM (inline truck) | SYS | PHYS | DIFF.
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
    final cat = item['category_name']?.toString().trim() ?? '';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final isLowOrCritical =
        status == 'low' || status == 'critical' || status == 'out';
    final deliveryKind = StockRowMetrics.deliveryIndicator(item);
    final diff = StockRowMetrics.diffQty(item);
    final deliveryCue = StockRowMetrics.inlineDeliveryCue(item);

    final metaLine = sub.isNotEmpty
        ? sub
        : cat.isNotEmpty
            ? cat
            : '';

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
              maxHeight: StockTableLayout.rowMinHeight,
            ),
            decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow)
                .copyWith(
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : StockTableLayout.rowFill,
              border: isLowOrCritical
                  ? const Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 3),
                    )
                  : deliveryKind == StockDeliveryIndicator.pending
                      ? const Border(
                          left: BorderSide(
                            color: Color(0xFFEA580C),
                            width: 3,
                          ),
                        )
                      : deliveryKind == StockDeliveryIndicator.delivered
                          ? const Border(
                              left: BorderSide(
                                color: Color(0xFF16A34A),
                                width: 3,
                              ),
                            )
                          : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: StockTableLayout.itemCellDecoration(),
                      padding: const EdgeInsets.fromLTRB(
                        StockTableLayout.cellHPadding,
                        5,
                        4,
                        5,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                              height: 1.12,
                            ),
                          ),
                          if (deliveryCue != null || metaLine.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  if (deliveryCue != null) ...[
                                    deliveryCue,
                                    if (metaLine.isNotEmpty)
                                      const SizedBox(width: 6),
                                  ],
                                  if (metaLine.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        metaLine,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: HexaDsType.label(9).copyWith(
                                          color: const Color(0xFF64748B),
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _boxedMetric(
                    StockRowMetrics.systemCellLabel(item),
                    StockRowMetrics.inlineStatusColor(item),
                  ),
                  _boxedMetric(
                    StockRowMetrics.physicalCellLabel(item),
                    const Color(0xFF0F766E),
                  ),
                  _boxedMetric(
                    StockRowMetrics.diffCellLabel(item),
                    StockRowMetrics.diffColor(diff),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boxedMetric(String primary, Color color) {
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          primary,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }
}
