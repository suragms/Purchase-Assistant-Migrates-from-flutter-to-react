import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';
import 'stock_status_badge.dart';
import 'stock_table_layout.dart';

/// Dense bordered warehouse stock row: ITEM | STOCK | STATUS.
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
    final codeRaw = item['item_code']?.toString().trim() ?? '';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final stockUnit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece';
    final status =
        (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    final missingBarcode = item['missing_barcode'] == true;
    final updatedAt = item['last_stock_updated_at']?.toString();
    final updatedBy = item['last_stock_updated_by']?.toString();
    final relative = formatStockRelativeTime(updatedAt);
    final hasPendingOrder = item['has_pending_order'] == true;
    final pendingDays = (item['pending_order_days'] as num?)?.toInt();

    final statusKind = StockStatusBadge.resolve(
      stockStatus: status,
      missingBarcode: missingBarcode,
      updatedAtIso: updatedAt,
    );
    final displayStatus = stockDisplayStatusFromApi(status);
    final isLowOrOut = displayStatus == StockDisplayStatus.low ||
        displayStatus == StockDisplayStatus.out;

    final metaParts = <String>[
      if (codeRaw.isNotEmpty) '#$codeRaw',
      if (relative.isNotEmpty) relative,
      if (!isStaffMode && updatedBy != null && updatedBy.isNotEmpty) updatedBy,
    ];

    String? ownerFooter;
    if (!isStaffMode) {
      final physical = coerceToDouble(item['physical_stock_qty']);
      final physicalDiff =
          coerceToDouble(item['physical_stock_difference_qty']);
      final purchased = coerceToDouble(item['period_purchased_qty']);
      if (item['physical_stock_qty'] != null && physical.isFinite) {
        final sign = physicalDiff >= 0 ? '+' : '';
        ownerFooter =
            'Physical ${formatStockQtyNumber(physical)} ${stockUnit.toUpperCase()}'
            ' • Diff $sign${formatStockQtyNumber(physicalDiff)}';
      } else if (purchased > 0) {
        final diff = cur - purchased;
        if (diff.abs() > 0.001) {
          final sign = diff >= 0 ? '+' : '';
          ownerFooter =
              'Purchased ${formatStockQtyNumber(purchased)} ${stockUnit.toUpperCase()}'
              ' • Diff $sign${formatStockQtyNumber(diff)}';
        }
      }
    }

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
              border: isLowOrOut
                  ? const Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 3),
                    )
                  : null,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 330;
                final stockCol = 92.0;
                final statusCol =
                    compact ? 52.0 : StockTableLayout.statusColWidth;
                final showDesktopMetrics =
                    desktop && constraints.maxWidth >= 760;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 5 : StockTableLayout.cellHPadding,
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
                                  sub.toLowerCase() !=
                                      name.trim().toLowerCase())
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
                                    color:
                                        statusKind == StockRowStatusKind.recent
                                            ? const Color(0xFF1565C0)
                                            : const Color(0xFF94A3B8),
                                  ),
                                ),
                              if (ownerFooter != null)
                                Text(
                                  ownerFooter,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: HexaDsType.label(11).copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: stockCol,
                        decoration: StockTableLayout.cellDecoration(),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: StockNumberDisplay(
                          qty: cur,
                          unit: stockUnit,
                          status: displayStatus,
                          hasPendingOrder: hasPendingOrder,
                          pendingDays: pendingDays,
                          fontSize: compact ? 13 : 14,
                        ),
                      ),
                      if (showDesktopMetrics) ...[
                        _metricCell(
                          item['physical_stock_qty'] == null
                              ? '-'
                              : formatStockQtyNumber(
                                  coerceToDouble(item['physical_stock_qty']),
                                ),
                        ),
                        _metricCell(
                          item['period_purchased_qty'] == null
                              ? '-'
                              : formatStockQtyNumber(
                                  coerceToDouble(item['period_purchased_qty']),
                                ),
                        ),
                        _metricCell(
                          item['physical_stock_difference_qty'] == null
                              ? '-'
                              : _signedQty(
                                  coerceToDouble(
                                    item['physical_stock_difference_qty'],
                                  ),
                                ),
                        ),
                      ],
                      SizedBox(
                        width: statusCol,
                        child: Center(
                          child: StockStatusBadge(kind: statusKind),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCell(String value) {
    return Container(
      width: StockTableLayout.desktopMetricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HexaDsType.label(11).copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  String _signedQty(double value) {
    if (!value.isFinite) return '-';
    final sign = value >= 0 ? '+' : '';
    return '$sign${formatStockQtyNumber(value)}';
  }
}
