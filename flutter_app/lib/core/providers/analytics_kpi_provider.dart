import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import '../utils/report_date_params.dart';
import 'reports_provider.dart' show reportsPurchasesNeedsLiveFetchProvider;

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

final Map<String, DateTime> _tradeSummaryFetchedAt = {};
final Map<String, AnalyticsKpi> _tradeSummaryCache = {};

String _tradeSummaryCacheKey(String bid, String from, String to) =>
    '$bid|$from|$to';

AnalyticsKpi _analyticsKpiFromSummaryMap(Map<String, dynamic> m) {
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
}

final analyticsKpiProvider =
    FutureProvider.autoDispose<AnalyticsKpi>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(t.cancel);
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final branch = ref.watch(shellCurrentBranchProvider);
  final needsLive = ref.watch(reportsPurchasesNeedsLiveFetchProvider);
  if (branch != ShellBranch.reports && !needsLive) {
    return const AnalyticsKpi(
      totalPurchase: 0,
      totalQtyBase: 0,
      totalProfit: 0,
      purchaseCount: 0,
    );
  }
  final api = ref.read(hexaApiProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final bid = session.primaryBusiness.id;
  final fromStr = fmt.format(range.from);
  final toStr = fmt.format(range.to);
  final cacheKey = _tradeSummaryCacheKey(bid, fromStr, toStr);
  final fetchedAt = _tradeSummaryFetchedAt[cacheKey];
  if (fetchedAt != null &&
      DateTime.now().difference(fetchedAt) < const Duration(seconds: 60)) {
    final cached = _tradeSummaryCache[cacheKey];
    if (cached != null) return cached;
  }
  final m = await api.tradePurchaseSummary(
    businessId: bid,
    from: fromStr,
    to: toStr,
    tzOffsetMinutes: localTzOffsetMinutes,
  );
  if (providerWasDisposed(disposed)) {
    return const AnalyticsKpi(
      totalPurchase: 0,
      totalQtyBase: 0,
      totalProfit: 0,
      purchaseCount: 0,
    );
  }
  final kpi = _analyticsKpiFromSummaryMap(m);
  _tradeSummaryFetchedAt[cacheKey] = DateTime.now();
  _tradeSummaryCache[cacheKey] = kpi;
  return kpi;
});
