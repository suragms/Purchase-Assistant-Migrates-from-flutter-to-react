import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import 'stock_table_layout.dart';

/// Opening stock row: ITEM | UNIT | OPENING | STATUS.
class OpeningStockTableRow extends StatelessWidget {
  const OpeningStockTableRow({
    super.key,
    required this.item,
    required this.onTap,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelected,
    this.onLongPress,
    this.onMissingBarcodeTap,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onMissingBarcodeTap;

  @override
  Widget build(BuildContext context) {
    final unitRaw =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? '';
    final unit = unitRaw.trim().isEmpty ? '—' : unitRaw.trim().toUpperCase();

    final name = item['name']?.toString() ?? '—';
    final sub = item['subcategory_name']?.toString().trim() ?? '';
    final code = item['item_code']?.toString().trim() ?? '';
    final barcodeState = item['barcode_state']?.toString() ?? 'ok';
    final missingBarcode = barcodeState == 'missing';

    final setupStatus =
        item['setup_status']?.toString() ?? 'pending'; // pending|completed
    final isCompleted = setupStatus == 'completed';

    final openingQty = item['opening_stock_qty'];
    final openingText = openingQty == null
        ? '—'
        : formatStockQtyForUnit(unitRaw, coerceToDouble(openingQty));

    final statusBg = isCompleted
        ? const Color(0xFF16A34A)
        : const Color(0xFFE65100);
    final statusFg = Colors.white;

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
            decoration: StockTableLayout.rowDecoration(isFirst: false),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        StockTableLayout.cellHPadding,
                        6,
                        6,
                        6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (selectionMode)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (_) => onToggleSelected?.call(),
                              ),
                            ),
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 18,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (sub.isNotEmpty)
                                  Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (code.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '#$code',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: HexaDsType.label(11).copyWith(
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                                if (missingBarcode) ...[
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: onMissingBarcodeTap,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Text(
                                      'No barcode',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: HexaDsType.label(11).copyWith(
                                        color: const Color(0xFF6A1B9A),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 60,
                    decoration: StockTableLayout.cellDecoration(),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      unit,
                      style: HexaDsType.label(11).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    width: 90,
                    decoration: StockTableLayout.cellDecoration(),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      openingText,
                      style: HexaDsType.label(11).copyWith(
                        fontWeight: FontWeight.w900,
                        color: isCompleted
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    width: 90,
                    alignment: Alignment.center,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg.withValues(alpha: 1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          isCompleted ? 'Completed' : 'Pending',
                          style: HexaDsType.label(11).copyWith(
                            color: statusFg,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
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
}

