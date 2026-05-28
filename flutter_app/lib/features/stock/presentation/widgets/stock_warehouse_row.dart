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
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final unit = StockRowMetrics.unit(item);
    final purchased = StockRowMetrics.purchasedQty(item);
    final stock = StockRowMetrics.stockQty(item);
    final physical = StockRowMetrics.physicalQty(item);
    final diff = StockRowMetrics.diffQty(item);
    final pending = StockRowMetrics.pendingDeliveryQty(item);
    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final updatedAt = item['last_stock_updated_at']?.toString();
    final updatedBy = item['last_stock_updated_by']?.toString();
    final relative = formatStockRelativeTime(updatedAt);
    final isLowOrCritical = status == 'low' || status == 'critical' || status == 'out';

    final metaParts = <String>[
      if (codeRaw.isNotEmpty) '#$codeRaw',
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
                  _boxedMetric(
                    formatStockQtyNumber(stock),
                    unit,
                    StockRowMetrics.inlineStatusColor(item),
                  ),
                  _boxedMetric(
                    purchased == null ? '—' : formatStockQtyNumber(purchased),
                    unit,
                    const Color(0xFF1A1A1A),
                  ),
                  _boxedMetric(
                    physical == null ? '—' : formatStockQtyNumber(physical),
                    unit,
                    const Color(0xFF0F766E),
                  ),
                  _boxedMetric(
                    _diffPrimary(diff),
                    _diffSecondary(diff),
                    StockRowMetrics.diffColor(diff),
                  ),
                  _boxedMetric(
                    _pendingPrimary(pending, item),
                    _pendingSecondary(item),
                    _pendingColor(pending, item),
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

  String _pendingPrimary(double? pending, Map<String, dynamic> item) {
    if (pending != null && pending > 0) {
      return formatStockQtyNumber(pending);
    }
    if (item['has_pending_order'] == true) return '•';
    return '—';
  }

  String _pendingSecondary(Map<String, dynamic> item) {
    if (item['has_pending_order'] != true) return '';
    final days = item['pending_order_days'];
    if (days is num && days > 0) return '${days.toInt()}d';
    return 'Wait';
  }

  Color _pendingColor(double? pending, Map<String, dynamic> item) {
    if ((pending ?? 0) > 0 || item['has_pending_order'] == true) {
      return const Color(0xFFE65100);
    }
    return const Color(0xFF64748B);
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
