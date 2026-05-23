import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import 'stock_table_layout.dart';

/// Column labels aligned with [StockQtyMetricTriple] / bordered rows.
class StockListColumnHeader extends StatelessWidget {
  const StockListColumnHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final hdr = HexaDsType.label(11).copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF475569),
      letterSpacing: 0.15,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 4, HexaOp.pageGutter, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE8E6E1),
          border: Border.all(color: StockTableLayout.borderColor),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text('Item', style: hdr)),
              SizedBox(
                width: StockTableLayout.metricWidth,
                child: Text('Purchased', textAlign: TextAlign.center, style: hdr),
              ),
              const SizedBox(width: StockTableLayout.metricGap),
              SizedBox(
                width: StockTableLayout.metricWidth,
                child: Text('Stock', textAlign: TextAlign.center, style: hdr),
              ),
              const SizedBox(width: StockTableLayout.metricGap),
              SizedBox(
                width: StockTableLayout.metricWidth,
                child: Text('Diff', textAlign: TextAlign.center, style: hdr),
              ),
              const SizedBox(width: StockTableLayout.actionsWidth - 8),
            ],
          ),
        ),
      ),
    );
  }
}
