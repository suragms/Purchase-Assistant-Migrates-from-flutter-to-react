import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';

/// Aligns with [StockQtyMetricTriple] columns on stock rows.
class StockListColumnHeader extends StatelessWidget {
  const StockListColumnHeader({super.key});

  static const _hdr = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: Color(0xFF475569),
    letterSpacing: 0.15,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 4, 56, 6),
      child: Row(
        children: const [
          Expanded(
            child: Text('Item', style: _hdr),
          ),
          SizedBox(
            width: 44,
            child: Text(
              'Purchased',
              textAlign: TextAlign.center,
              style: _hdr,
            ),
          ),
          SizedBox(width: 4),
          SizedBox(
            width: 44,
            child: Text(
              'Stock',
              textAlign: TextAlign.center,
              style: _hdr,
            ),
          ),
          SizedBox(width: 4),
          SizedBox(
            width: 44,
            child: Text(
              'Diff',
              textAlign: TextAlign.center,
              style: _hdr,
            ),
          ),
        ],
      ),
    );
  }
}
