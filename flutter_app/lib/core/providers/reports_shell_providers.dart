import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/reports/reports_bi_tab.dart';

/// Shell tab state survives URL query rebuilds (prevents tab-switch shake).
final reportsShellTabProvider = StateProvider<ReportsBiTab>(
  (ref) => ReportsBiTab.overview,
  name: 'reportsShellTab',
);

/// Stock tab section (slow / dead) without full route rebuild.
final reportsStockSectionProvider = StateProvider<String>(
  (ref) => 'slow',
  name: 'reportsStockSection',
);
