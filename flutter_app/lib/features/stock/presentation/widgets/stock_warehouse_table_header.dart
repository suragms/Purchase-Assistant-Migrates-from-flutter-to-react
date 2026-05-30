import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_table_layout.dart';

/// Warehouse table header: item + metric columns (staff vs owner).
class StockWarehouseTableHeader extends StatelessWidget {
  const StockWarehouseTableHeader({
    super.key,
    this.isStaffMode = false,
  });

  final bool isStaffMode;

  @override
  Widget build(BuildContext context) {
    final hdr = HexaDsType.label(9).copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF475569),
      letterSpacing: 0.2,
      height: 1.15,
    );

    const metrics = ['SYSTEM', 'PHYS', 'DIFF'];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HexaResponsive.pageGutter(context, operational: true),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StockTableLayout.headerFill,
          border: Border.all(color: StockTableLayout.borderColor),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: StockTableLayout.itemCellDecoration(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: StockTableLayout.cellHPadding,
                    vertical: 6,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text('ITEM', style: hdr),
                ),
              ),
              for (final label in metrics) _metricHeader(label, hdr),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricHeader(String label, TextStyle style) {
    return Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Text(label, style: style, textAlign: TextAlign.center),
    );
  }
}
