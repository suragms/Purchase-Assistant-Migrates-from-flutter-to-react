import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_responsive.dart';

enum ReportsLayoutMode { phone, tablet, desktop }

ReportsLayoutMode reportsLayoutMode(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1024) return ReportsLayoutMode.desktop;
  if (w >= 768) return ReportsLayoutMode.tablet;
  return ReportsLayoutMode.phone;
}

/// Max header height per spec.
const double kReportsHeaderHeight = 56;

/// Minimum chart panel height.
const double kReportsChartMinHeight = 280;

/// Compact item/purchase row height target.
const double kReportsRowExtent = 76;

extension ReportsLayoutX on BuildContext {
  bool get isReportsDesktop => isDesktopLayout;
  bool get isReportsTablet {
    final w = MediaQuery.sizeOf(this).width;
    return w >= 768 && w < 1024;
  }
}
