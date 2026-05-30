import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../json_coerce.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import 'analytics_kpi_provider.dart';

/// One calendar day of summed line profit (for Overview trend chart).
typedef AnalyticsDailyProfitPoint = ({DateTime day, double profit});

/// Last 30 calendar days ending on [analyticsDateRangeProvider].to (inclusive).
/// Uses `GET …/reports/trade-daily-profit` (server line-profit SSOT).
final analyticsDailyProfitProvider =
    FutureProvider.autoDispose<List<AnalyticsDailyProfitPoint>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final end = DateTime(range.to.year, range.to.month, range.to.day);
  final start = end.subtract(const Duration(days: 29));
  final fmt = DateFormat('yyyy-MM-dd');
  final fromS = fmt.format(start);
  final toS = fmt.format(end);
  final raw = await ref.read(hexaApiProvider).tradeReportDailyProfit(
        businessId: session.primaryBusiness.id,
        from: fromS,
        to: toS,
      );
  final byDay = <String, double>{};
  for (final row in raw) {
    final ds = row['d']?.toString();
    if (ds == null || ds.isEmpty) continue;
    byDay[ds] = coerceToDouble(row['profit']);
  }
  final out = <AnalyticsDailyProfitPoint>[];
  for (var i = 0; i < 30; i++) {
    final d = start.add(Duration(days: i));
    final key = fmt.format(d);
    out.add((day: d, profit: byDay[key] ?? 0));
  }
  return out;
});

final analyticsItemsTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportItems(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsCategoriesTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportCategories(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

/// Trade-backed subcategory (CategoryType) rows — use for Home donut + subcategory view.
final analyticsTypesTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportTypes(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsSuppliersTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportSuppliers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsBrokersTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsBrokers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

/// Heuristic insight: highest estimated purchase-volume item × supplier with lowest avg landing vs peer average.
final analyticsBestSupplierInsightProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final items = await ref.watch(analyticsItemsTableProvider.future);
  final suppliers = await ref.watch(analyticsSuppliersTableProvider.future);
  if (items.isEmpty || suppliers.isEmpty) return null;
  Map<String, dynamic>? topByVol;
  var bestVol = -1.0;
  for (final r in items) {
    final al = coerceToDouble(r['avg_landing']);
    final tq = coerceToDouble(r['total_qty']);
    final vol = al * tq;
    if (vol > bestVol) {
      bestVol = vol;
      topByVol = r;
    }
  }
  final itemName = topByVol?['item_name']?.toString() ?? '';
  if (itemName.isEmpty) return null;
  final supList = List<Map<String, dynamic>>.from(suppliers);
  supList.sort((a, b) => (coerceToDoubleNullable(a['avg_landing']) ?? 1e18)
      .compareTo(coerceToDoubleNullable(b['avg_landing']) ?? 1e18));
  final best = supList.first;
  final sname = best['supplier_name']?.toString() ?? '';
  final savg = coerceToDouble(best['avg_landing']);
  var sum = 0.0;
  for (final s in supList) {
    sum += coerceToDouble(s['avg_landing']);
  }
  final overall = supList.isEmpty ? savg : sum / supList.length;
  final delta = overall - savg;
  final fmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  if (delta.abs() < 0.01) {
    return 'High-volume item: $itemName — $sname has best avg landing (${fmt.format(savg)}) vs peers.';
  }
  return 'Best supplier for $itemName: $sname (${fmt.format(savg)} avg) — ${fmt.format(delta.abs())} ${delta >= 0 ? 'cheaper' : 'higher'} than average landing.';
});
