import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/operational_date_format.dart';
import '../../../../core/utils/unit_utils.dart';
import 'edit_item_code_sheet.dart';
import 'stock_qty_metric_column.dart';
import 'stock_table_layout.dart';

/// Dense 72dp warehouse stock row.
class StockOperationalRow extends ConsumerWidget {
  const StockOperationalRow({
    super.key,
    required this.item,
    required this.includePeriod,
    required this.onTap,
    this.onAction,
    this.canEdit = true,
    this.bordered = false,
    this.isFirstRow = false,
  });

  final Map<String, dynamic> item;
  final bool includePeriod;
  final VoidCallback onTap;
  final VoidCallback? onAction;
  final bool canEdit;
  final bool bordered;
  final bool isFirstRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final codeRaw = item['item_code']?.toString().trim() ?? '';
    final missingCode = item['missing_item_code'] == true || codeRaw.isEmpty;
    final cat = item['category_name']?.toString() ?? '';
    final sub = item['subcategory_name']?.toString() ?? '';
    final supplier = item['supplier_name']?.toString() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final stockUnit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece';
    final kgPerBag = coerceToDouble(item['default_kg_per_bag']);
    final stockKg = coerceToDouble(item['current_stock_kg']);
    final nowDual = dualStockDisplay(
      qty: cur,
      unit: stockUnit,
      kgPerBag: kgPerBag > 0 ? kgPerBag : null,
      currentStockKg: stockKg > 0 ? stockKg : null,
    );

    final purchased = includePeriod
        ? coerceToDouble(item['period_purchased_qty'])
        : coerceToDouble(item['purchased_today_qty']);

    // Diff = physical stock minus purchased in period (sales / not yet received show negative).
    final moved = includePeriod ? cur - purchased : 0.0;

    final status =
        (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final highlightCurrent =
        status == 'low' || status == 'critical' || status == 'out';
    final daysSinceRaw = item['days_since_last_purchase'];
    final daysSince = daysSinceRaw is num ? daysSinceRaw.toInt() : null;
    final purchaseAgingColor = daysSince == null
        ? null
        : daysSince <= 7
            ? const Color(0xFF3B6D11)
            : daysSince <= 30
                ? const Color(0xFFE65100)
                : const Color(0xFFA32D2D);
    final missingBarcode = item['missing_barcode'] == true;
    final badge = _statusBadge(status);
    final updateLine = formatStockRowUpdateLine(
      updatedBy: item['last_stock_updated_by']?.toString(),
      updatedAtIso: item['last_stock_updated_at']?.toString(),
    );

    // Subcategory only — avoid "Essentials · Sugar · Sugar" noise.
    final subOnly = sub.isNotEmpty
        ? sub
        : (cat.isNotEmpty ? cat : '');
    final catLine = [
      if (subOnly.isNotEmpty &&
          subOnly.toLowerCase() != name.trim().toLowerCase())
        subOnly,
      supplier,
    ].where((s) => s.isNotEmpty).join(' • ');
    final itemId = item['id']?.toString() ?? '';
    final hid = item['last_purchase_human_id']?.toString() ?? '';
    final delivered = item['last_purchase_delivered'];
    final pendingDelivery = delivered == false && hid.isNotEmpty;
    final boughtPrimary = stockDisplayPrimary(
      purchased,
      stockUnit,
    );
    final boughtLine = includePeriod && purchased > 0
        ? 'Bought $boughtPrimary this period'
        : '';

    final row = Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 96),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: bordered ? 8 : HexaOp.pageGutter,
              vertical: 6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HexaDsType.heading(15),
                          ),
                          GestureDetector(
                            onTap: missingCode
                                ? () => showEditItemCodeSheet(
                                      context: context,
                                      ref: ref,
                                      itemId: itemId,
                                      itemName: name,
                                      currentCode: codeRaw,
                                    )
                                : null,
                            child: Text(
                              missingCode ? 'Missing item code' : codeRaw,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: missingCode
                                    ? const Color(0xFFA32D2D)
                                    : Colors.black54,
                                fontWeight: missingCode
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (missingBarcode)
                                _badge(
                                  'NO BARCODE',
                                  const Color(0xFFF3E8FF),
                                  const Color(0xFF7E22CE),
                                )
                              else
                                badge,
                              if (pendingDelivery)
                                _badge(
                                  'PENDING',
                                  const Color(0xFFFFF3E0),
                                  const Color(0xFFE65100),
                                ),
                            ],
                          ),
                          if (boughtLine.isNotEmpty)
                            Text(
                              boughtLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF3B6D11),
                              ),
                            ),
                          if (catLine.isNotEmpty)
                            Text(
                              catLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                        ],
                      ),
                    ),
                    StockQtyMetricTriple(
                      purchased: purchased,
                      current: cur,
                      moved: moved,
                      highlightCurrent: highlightCurrent,
                      currentSubtitle: nowDual.secondary,
                      showColumnLabels: false,
                    ),
                    if (daysSince != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Tooltip(
                          message: 'Days since last purchase: $daysSince',
                          child: _badge(
                            '${daysSince}d',
                            purchaseAgingColor!.withValues(alpha: 0.12),
                            purchaseAgingColor,
                          ),
                        ),
                      ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Colors.black26,
                    ),
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        tooltip: 'Actions',
                        onPressed: onAction ?? onTap,
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                if (updateLine.isNotEmpty)
                  Text(
                    updateLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black38),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!bordered) return row;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
      child: DecoratedBox(
        decoration: StockTableLayout.rowDecoration(isFirst: isFirstRow),
        child: row,
      ),
    );
  }

  Widget _statusBadge(String status) {
    String label;
    Color bg;
    Color fg;
    switch (status) {
      case 'low':
        label = 'LOW';
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFBA7517);
        break;
      case 'critical':
        label = 'CRITICAL';
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFA32D2D);
        break;
      case 'out':
        label = 'OUT';
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFA32D2D);
        break;
      default:
        label = 'OK';
        bg = const Color(0xFFE8F5E0);
        fg = const Color(0xFF3B6D11);
    }
    return _badge(label, bg, fg);
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
