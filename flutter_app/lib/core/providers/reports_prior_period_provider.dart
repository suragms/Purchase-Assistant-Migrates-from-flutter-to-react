import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';
import 'home_dashboard_provider.dart';

/// Same-length window immediately before the current [analyticsDateRangeProvider].
class ReportsPriorPeriodDelta {
  const ReportsPriorPeriodDelta({
    required this.priorFrom,
    required this.priorTo,
    required this.currentProfit,
    required this.priorProfit,
    required this.currentPurchase,
    required this.priorPurchase,
  });

  final DateTime priorFrom;
  final DateTime priorTo;
  final double currentProfit;
  final double priorProfit;
  final double currentPurchase;
  final double priorPurchase;

  /// % change vs prior window; null if prior was ~0 (treat as "no baseline").
  double? profitPctVsPrior() => _pctDelta(currentProfit, priorProfit);

  double? purchasePctVsPrior() => _pctDelta(currentPurchase, priorPurchase);
}

double? _pctDelta(double cur, double prev) {
  if (prev.abs() < 1e-9) {
    if (cur.abs() < 1e-9) return 0;
    return null;
  }
  return (cur - prev) / prev.abs() * 100.0;
}

/// Fetches trade-summary + daily profit for current and prior equal-length ranges.
final reportsPriorPeriodDeltaProvider =
    FutureProvider.autoDispose<ReportsPriorPeriodDelta>((ref) async {
  if (!ref.watch(homePriorPeriodFetchEnabledProvider)) {
    final range = ref.watch(analyticsDateRangeProvider);
    final from = DateTime(range.from.year, range.from.month, range.from.day);
    final to = DateTime(range.to.year, range.to.month, range.to.day);
    final days = to.difference(from).inDays + 1;
    final priorTo = from.subtract(const Duration(days: 1));
    final priorFrom = priorTo.subtract(Duration(days: days - 1));
    return ReportsPriorPeriodDelta(
      priorFrom: priorFrom,
      priorTo: priorTo,
      currentProfit: 0,
      priorProfit: 0,
      currentPurchase: 0,
      priorPurchase: 0,
    );
  }
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final from = DateTime(range.from.year, range.from.month, range.from.day);
  final to = DateTime(range.to.year, range.to.month, range.to.day);
  final days = to.difference(from).inDays + 1;
  final priorTo = from.subtract(const Duration(days: 1));
  final priorFrom = priorTo.subtract(Duration(days: days - 1));

  final fmt = DateFormat('yyyy-MM-dd');
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final curFrom = fmt.format(from);
  final curTo = fmt.format(to);
  final prevFrom = fmt.format(priorFrom);
  final prevTo = fmt.format(priorTo);

  Future<double> sumProfit(String f, String t) async {
    final rows = await api.tradeReportDailyProfit(
      businessId: bid,
      from: f,
      to: t,
    );
    var sum = 0.0;
    for (final row in rows) {
      sum += (row['profit'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  final results = await Future.wait([
    api.tradePurchaseSummary(businessId: bid, from: curFrom, to: curTo),
    api.tradePurchaseSummary(businessId: bid, from: prevFrom, to: prevTo),
    sumProfit(curFrom, curTo),
    sumProfit(prevFrom, prevTo),
  ]);
  final cur = results[0] as Map<String, dynamic>;
  final prev = results[1] as Map<String, dynamic>;

  return ReportsPriorPeriodDelta(
    priorFrom: priorFrom,
    priorTo: priorTo,
    currentProfit: results[2] as double,
    priorProfit: results[3] as double,
    currentPurchase: (cur['total_purchase'] as num?)?.toDouble() ?? 0,
    priorPurchase: (prev['total_purchase'] as num?)?.toDouble() ?? 0,
  );
});
