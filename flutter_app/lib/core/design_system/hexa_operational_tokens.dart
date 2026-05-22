import 'package:flutter/material.dart';

import 'hexa_ds_tokens.dart';

/// Compact warehouse/operational spacing — use on home, stock, scanner, bulk print.
/// Does not replace [HexaDsLayout] (purchase wizard keeps 24dp gutters).
abstract final class HexaOp {
  HexaOp._();

  static const double pageGutter = 16;
  static const double cardPadding = 14;
  static const double sectionGap = 16;
  static const double cardGap = 12;
  static const double buttonHeight = 44;
  static const double chipHeight = 36;
  static const double listRowMin = 64;
  static const double listRowMax = 72;
  static const double collapsedHeader = 52;
  static const double bottomNavMax = 60;
  static const double fabSize = 56;
  static const double quickActionIcon = 48;

  static EdgeInsets get pagePadding =>
      const EdgeInsets.fromLTRB(pageGutter, 8, pageGutter, 16);

  static TextStyle heading(BuildContext context) =>
      HexaDsType.heading(20, color: HexaDsColors.textPrimary);

  static TextStyle cardTitle(BuildContext context) =>
      HexaDsType.heading(16, color: HexaDsColors.textPrimary);

  static TextStyle body(BuildContext context) => HexaDsType.body(14);

  static TextStyle caption(BuildContext context) => HexaDsType.label(11);
}
