import 'package:flutter/material.dart';

/// Shared column geometry for stock list header + bordered rows.
abstract final class StockTableLayout {
  static const double metricWidth = 44;
  static const double metricGap = 4;
  static const double actionsWidth = 56;
  static const Color borderColor = Color(0xFFE0DDD8);
  static const Color rowFill = Colors.white;

  static const BorderSide cellBorder = BorderSide(color: borderColor, width: 1);

  static BoxDecoration rowDecoration({bool isFirst = false}) {
    return BoxDecoration(
      color: rowFill,
      border: Border(
        left: cellBorder,
        right: cellBorder,
        top: isFirst ? cellBorder : BorderSide.none,
        bottom: cellBorder,
      ),
    );
  }
}
