import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/operational_date_format.dart';
import '../../../../core/utils/unit_utils.dart';
import 'edit_item_code_sheet.dart';

/// Dense 72dp warehouse stock row.
class StockOperationalRow extends ConsumerWidget {
  const StockOperationalRow({
    super.key,
    required this.item,
    required this.includePeriod,
    required this.onTap,
    this.canEdit = true,
  });

  final Map<String, dynamic> item;
  final bool includePeriod;
  final VoidCallback onTap;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = item['name']?.toString() ?? '—';
    final codeRaw = item['item_code']?.toString().trim() ?? '';
    final missingCode = item['missing_item_code'] == true || codeRaw.isEmpty;
    final unit = item['unit']?.toString() ?? '';
    final cat = item['category_name']?.toString() ?? '';
    final sub = item['subcategory_name']?.toString() ?? '';
    final supplier = item['supplier_name']?.toString() ?? '';
    final cur = coerceToDouble(item['current_stock']);
    final kgPerBag = coerceToDoubleNullable(item['default_kg_per_bag']) ??
        coerceToDoubleNullable(item['kg_per_bag']);

    final purchased = includePeriod
        ? coerceToDouble(item['period_purchased_qty'])
        : coerceToDouble(item['purchased_today_qty']);

    final stockPrimary = stockDisplayPrimary(cur, unit);
    final stockSecondary = stockDisplaySecondary(cur, unit, kgPerBag, null);
    final purchasedLabel = purchased > 0
        ? '+${stockDisplayPrimary(purchased, unit)}'
        : '';
    final movement = purchased > 0 ? cur - purchased : -coerceToDouble(item['usage_today_qty']);
    final movementLabel = movement == 0
        ? '—'
        : '${movement > 0 ? '+' : ''}${movement == movement.roundToDouble() ? movement.round() : movement.toStringAsFixed(1)}';

    final status = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    final missingBarcode = item['missing_barcode'] == true;
    final badge = _statusBadge(status, missingBarcode: missingBarcode);
    final updateLine = formatStockRowUpdateLine(
      updatedBy: item['last_stock_updated_by']?.toString(),
      updatedAtIso: item['last_stock_updated_at']?.toString(),
    );

    final catLine = [
      [cat, sub].where((s) => s.isNotEmpty).join(' · '),
      supplier,
    ].where((s) => s.isNotEmpty).join(' • ');
    final itemId = item['id']?.toString() ?? '';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 78),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HexaOp.pageGutter,
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
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
                          if (unit.toLowerCase() == 'bag' &&
                              kgPerBag != null &&
                              kgPerBag > 0)
                            Text(
                              '${kgPerBag == kgPerBag.roundToDouble() ? kgPerBag.round() : kgPerBag}kg/bag',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black38,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Purchased',
                            style: TextStyle(fontSize: 9, color: Colors.black38),
                          ),
                          if (purchasedLabel.isNotEmpty)
                            Text(
                              purchasedLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3B6D11),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          _tinyValue('Current', stockPrimary),
                          if (stockSecondary != null)
                            Text(
                              stockSecondary
                                  .replaceAll('(', '')
                                  .replaceAll(')', ''),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _tinyValue('Moved', movementLabel),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        badge,
                      ],
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
  }

  Widget _tinyValue(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.black38),
          textAlign: TextAlign.center,
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _statusBadge(String status, {required bool missingBarcode}) {
    String label;
    Color bg;
    Color fg;
    if (missingBarcode) {
      return _badge('NO BARCODE', const Color(0xFFF3E8FF), const Color(0xFF7E22CE));
    }
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
