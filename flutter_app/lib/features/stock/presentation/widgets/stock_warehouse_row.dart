import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_row_metrics.dart';
import 'stock_status_badge.dart' show formatStockRelativeTime;
import 'stock_table_layout.dart';

/// Warehouse operational row — tap row for actions sheet.
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
    final cat = item['category_name']?.toString().trim() ?? '';
    final system = StockRowMetrics.systemQty(item);
    final physical = StockRowMetrics.physicalQty(item);
    final diff = StockRowMetrics.diffQty(item);
    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final updatedAt = item['last_stock_updated_at']?.toString();
    final updatedBy = item['last_stock_updated_by']?.toString();
    final relative = formatStockRelativeTime(updatedAt);
    final isLowOrCritical = status == 'low' || status == 'critical' || status == 'out';

    final openingLabel = StockRowMetrics.openingLabel(item);
    final delivery = StockRowMetrics.deliveryMetaLine(item);

    final metaParts = <String>[
      if (codeRaw.isNotEmpty) '#$codeRaw',
      if (cat.isNotEmpty) cat,
      if (openingLabel.isNotEmpty) openingLabel,
      if (delivery.isNotEmpty) delivery,
      if (relative.isNotEmpty) relative,
      if (!isStaffMode && updatedBy != null && updatedBy.isNotEmpty) updatedBy,
    ];

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
              color: isSelected
                  ? const Color(0xFFEFF6FF)
                  : StockTableLayout.rowFill,
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
                    child: Container(
                      decoration: StockTableLayout.itemCellDecoration(),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A1A),
                              height: 1.2,
                            ),
                          ),
                          if (metaParts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                metaParts.join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.label(10).copyWith(
                                  color: const Color(0xFF64748B),
                                  height: 1.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _boxedMetric(
                    formatStockQtyNumber(system),
                    '',
                    StockRowMetrics.inlineStatusColor(item),
                  ),
                  _boxedMetric(
                    physical == null ? '—' : formatStockQtyNumber(physical),
                    physical == null ? 'Not counted' : '',
                    const Color(0xFF0F766E),
                  ),
                  _boxedMetric(
                    _diffPrimary(diff),
                    _diffSecondary(diff),
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

  String _diffPrimary(double diff) {
    if (!diff.isFinite) return '—';
    if (diff.abs() < 0.001) return '0';
    final sign = diff > 0 ? '+' : '';
    return '$sign${formatStockQtyNumber(diff)}';
  }

  String _diffSecondary(double diff) {
    if (!diff.isFinite) return '';
    if (diff.abs() < 0.001) return 'OK';
    return diff > 0 ? 'Excess' : 'Deficit';
  }

  Widget _boxedMetric(String primary, String secondary, Color color) {
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: StockTableLayout.metricColWidth - 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                primary,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              if (secondary.isNotEmpty)
                Text(
                  secondary,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: HexaDsType.label(8).copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
