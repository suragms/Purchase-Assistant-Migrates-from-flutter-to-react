import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_row_metrics.dart';
import 'stock_table_layout.dart';

/// Dense bordered warehouse stock row: ITEM | SYSTEM | PHYS | DIFF.
class StockTableRow extends StatelessWidget {
  const StockTableRow({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.isStaffMode = true,
    this.isFirstRow = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isStaffMode;
  final bool isFirstRow;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final status =
        (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final isLowOrCritical =
        status == 'low' || status == 'critical' || status == 'out';
    final deliveryKind = StockRowMetrics.deliveryIndicator(item);
    final diff = StockRowMetrics.diffQty(item);
    final deliveryCue = StockRowMetrics.inlineDeliveryCue(item);
    final activityMeta = StockRowMetrics.lastActivityMetaLine(item);

    final metaLine = activityMeta ??
        (sub.isNotEmpty && sub.toLowerCase() != name.trim().toLowerCase()
            ? sub
            : '');

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HexaResponsive.pageGutter(context, operational: true),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: StockTableLayout.rowMinHeight,
            ),
            decoration:
                StockTableLayout.rowDecoration(isFirst: isFirstRow).copyWith(
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
                  _metricCell(
                    StockRowMetrics.systemCellLabel(item),
                    StockRowMetrics.inlineStatusColor(item),
                  ),
                  _metricCell(
                    StockRowMetrics.physicalCellLabel(item),
                    const Color(0xFF0F766E),
                  ),
                  _metricCell(
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

  Widget _metricCell(String value, Color color) {
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
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
