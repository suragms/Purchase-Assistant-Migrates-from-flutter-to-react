import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
import 'package:share_plus/share_plus.dart';

/// Sort key for trend strings (`up` / `flat` / `down`) used on analytics tabs.
int analyticsTrendSortKey(Map<String, dynamic> r) {
  switch (r['trend']?.toString()) {
    case 'up':
      return 2;
    case 'flat':
      return 1;
    case 'down':
      return 0;
    default:
      return -1;
  }
}

/// Stable sort for breakdown tables (items / categories / suppliers / brokers).
List<Map<String, dynamic>> sortedReportRows(
  List<Map<String, dynamic>> rows,
  String mode,
  bool asc,
  num Function(Map<String, dynamic> r) profitKey,
) {
  final o = List<Map<String, dynamic>>.from(rows);
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (mode) {
      case 'best':
        return (a['best_item_name'] ?? '')
            .toString()
            .compareTo((b['best_item_name'] ?? '').toString());
      case 'type':
        return (a['type_name'] ?? '')
            .toString()
            .compareTo((b['type_name'] ?? '').toString());
      case 'name':
        return (a['item_name'] ??
                a['category'] ??
                a['supplier_name'] ??
                a['broker_name'] ??
                '')
            .toString()
            .compareTo((b['item_name'] ??
                    b['category'] ??
                    b['supplier_name'] ??
                    b['broker_name'] ??
                    '')
                .toString());
      case 'qty':
        return ((a['total_qty'] as num?) ?? 0)
            .compareTo((b['total_qty'] as num?) ?? 0);
      case 'lines':
        return ((a['line_count'] as num?) ?? 0)
            .compareTo((b['line_count'] as num?) ?? 0);
      case 'deals':
        return ((a['deals'] as num?) ?? 0).compareTo((b['deals'] as num?) ?? 0);
      case 'avg':
        return ((a['avg_landing'] as num?) ?? 0)
            .compareTo((b['avg_landing'] as num?) ?? 0);
      case 'commission':
        return ((a['total_commission'] as num?) ?? 0)
            .compareTo((b['total_commission'] as num?) ?? 0);
      case 'margin':
        return ((a['margin_pct'] as num?) ?? 0)
            .compareTo((b['margin_pct'] as num?) ?? 0);
      case 'trend':
        return analyticsTrendSortKey(a).compareTo(analyticsTrendSortKey(b));
      case 'commission_pct':
        return ((a['commission_pct_of_profit'] as num?) ?? 0)
            .compareTo((b['commission_pct_of_profit'] as num?) ?? 0);
      case 'profit':
      default:
        return profitKey(a).compareTo(profitKey(b));
    }
  }

  o.sort((a, b) {
    final c = cmp(a, b);
    return asc ? c : -c;
  });
  return o;
}

String analyticsCsvCell(String value) {
  final s = value.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
  if (s.contains(',') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

Future<void> shareAnalyticsReportCsv({
  required String title,
  required List<String> headers,
  required List<Map<String, dynamic>> rows,
  required List<String Function(Map<String, dynamic> r)> columns,
}) async {
  final buf = StringBuffer();
  buf.writeln(headers.map(analyticsCsvCell).join(','));
  for (final r in rows) {
    buf.writeln(columns.map((c) => analyticsCsvCell(c(r))).join(','));
  }
  await Share.share(buf.toString(), subject: title);
}

Color analyticsMarginStripeColor(double? m) {
  if (m == null) return Colors.transparent;
  if (m >= 15) return HexaColors.profit.withValues(alpha: 0.85);
  if (m >= 5) return HexaColors.accentAmber.withValues(alpha: 0.9);
  return HexaColors.loss.withValues(alpha: 0.75);
}
