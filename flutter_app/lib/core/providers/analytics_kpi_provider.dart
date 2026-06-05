import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import '../utils/report_date_params.dart';

/// Selected date range for the Analytics tab (`from`/`to` inclusive calendar days).
/// Default matches Home “Month”: last 30 days through today (`homePeriodRange`).
final analyticsDateRangeProvider =
    StateProvider<({DateTime from, DateTime to})>((ref) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return (
    from: today.subtract(const Duration(days: 29)),
    to: today,
  );
});

class AnalyticsKpi {
  const AnalyticsKpi({
    required this.totalPurchase,
    required this.totalQtyBase,
    required this.totalProfit,
    required this.purchaseCount,
    this.totalKg = 0,
    this.totalBags = 0,
    this.totalBoxes = 0,
    this.totalTins = 0,
  });

  final double totalPurchase;
  final double totalQtyBase;
  final double totalProfit;
  final int purchaseCount;
  final double totalKg;
  final double totalBags;
  final double totalBoxes;
  final double totalTins;
}

final analyticsKpiProvider =
    FutureProvider.autoDispose<AnalyticsKpi>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final api = ref.read(hexaApiProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final m = await api.tradePurchaseSummary(
    businessId: session.primaryBusiness.id,
    from: fmt.format(range.from),
    to: fmt.format(range.to),
    tzOffsetMinutes: localTzOffsetMinutes,
  );
  final u = m['unit_totals'];
  Map<String, dynamic> ut = {};
  if (u is Map) {
    ut = Map<String, dynamic>.from(u);
  }
  return AnalyticsKpi(
    totalPurchase: coerceToDouble(m['total_purchase']),
    totalQtyBase: coerceToDouble(m['total_qty']),
    totalProfit: 0,
    purchaseCount: coerceToInt(m['deals']),
    totalKg: coerceToDouble(ut['total_kg']),
    totalBags: coerceToDouble(ut['total_bags']),
    totalBoxes: coerceToDouble(ut['total_boxes']),
    totalTins: coerceToDouble(ut['total_tins']),
  );
});
