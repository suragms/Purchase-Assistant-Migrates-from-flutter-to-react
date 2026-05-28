import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_table_layout.dart';

/// Warehouse table header: ITEM | PURCHASE | STOCK | DIFF.
class StockWarehouseTableHeader extends StatelessWidget {
  const StockWarehouseTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final hdr = HexaDsType.label(10).copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF475569),
      letterSpacing: 0.3,
    );

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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: StockTableLayout.cellHPadding,
                    vertical: 6,
                  ),
                  child: Text('ITEM', style: hdr),
                ),
              ),
              _metricHeader('BOUGHT', hdr),
              _metricHeader('STOCK', hdr),
              _metricHeader('Δ', hdr),
              SizedBox(
                width: MediaQuery.sizeOf(context).width >= 340
                    ? StockTableLayout.actionsWidth
                    : 8,
              ),
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
