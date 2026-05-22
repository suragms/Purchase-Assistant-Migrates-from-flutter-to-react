import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart';

List<Map<String, dynamic>> _filterAuditsToHomePeriod(
  Ref ref,
  List<Map<String, dynamic>> rows,
) {
  final range = homePeriodRange(
    ref.read(homePeriodProvider),
    custom: ref.read(homeCustomDateRangeProvider),
  );
  return rows.where((a) {
    final atRaw = a['created_at']?.toString() ?? a['at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw)?.toLocal() : null;
    if (at == null) return false;
    return !at.isBefore(range.start) && at.isBefore(range.end);
  }).toList();
}

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Point-in-time on-hand stock totals (landing-cost valuation from backend).
class HomeInventorySummary {
  const HomeInventorySummary({
    required this.totalValueInr,
    required this.bags,
    required this.boxes,
    required this.tins,
    required this.kg,
    required this.itemCount,
  });

  final double totalValueInr;
  final double bags;
  final double boxes;
  final double tins;
  final double kg;
  final int itemCount;

  static const empty = HomeInventorySummary(
    totalValueInr: 0,
    bags: 0,
    boxes: 0,
    tins: 0,
    kg: 0,
    itemCount: 0,
  );

  factory HomeInventorySummary.fromJson(Map<String, dynamic> m) {
    return HomeInventorySummary(
      totalValueInr: coerceToDouble(m['total_value_inr']),
      bags: coerceToDouble(m['bags']),
      boxes: coerceToDouble(m['boxes']),
      tins: coerceToDouble(m['tins']),
      kg: coerceToDouble(m['kg']),
      itemCount: coerceToInt(m['item_count']),
    );
  }
}

final homeInventorySummaryProvider =
    FutureProvider.autoDispose<HomeInventorySummary>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) {
    return HomeInventorySummary.empty;
  }
  final session = ref.watch(sessionProvider);
  if (session == null) return HomeInventorySummary.empty;
  final raw = await ref.read(hexaApiProvider).stockInventorySummary(
        businessId: session.primaryBusiness.id,
      );
  return HomeInventorySummary.fromJson(raw);
});

/// Today-only dashboard row for the owner home stats strip (not tied to [homePeriodProvider]).
final homeTodayDashboardDataProvider =
    FutureProvider.autoDispose<HomeDashboardData>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) {
    return HomeDashboardData.empty;
  }
  final session = ref.watch(sessionProvider);
  if (session == null) return HomeDashboardData.empty;
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final from = _apiDate(day);
  final to = from;
  final snap = await ref.read(hexaApiProvider).reportsHomeOverview(
        businessId: session.primaryBusiness.id,
        from: from,
        to: to,
        compact: true,
        shellBundle: false,
      );
  return homeDashboardDataFromApiSnapshot(HomePeriod.today, snap);
});

/// Single parallel fetch for low + critical counts (avoids duplicate sequential home polls).
final stockAlertCountsProvider =
    FutureProvider.autoDispose<({int low, int critical})>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return (low: 0, critical: 0);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final results = await Future.wait([
    api.listStock(businessId: bid, page: 1, perPage: 1, status: 'low'),
    api.listStock(businessId: bid, page: 1, perPage: 1, status: 'critical'),
  ]);
  return (
    low: coerceToInt(results[0]['total']),
    critical: coerceToInt(results[1]['total']),
  );
});

final stockLowCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final c = await ref.watch(stockAlertCountsProvider.future);
  return c.low;
});

final stockCriticalCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final c = await ref.watch(stockAlertCountsProvider.future);
  return c.critical;
});

/// Top low-stock rows (server sorts by stock vs reorder).
final stockLowTopHomeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final m = await ref.read(hexaApiProvider).listStockLow(
        businessId: session.primaryBusiness.id,
        page: 1,
        perPage: 6,
      );
  final items = m['items'];
  if (items is! List) return [];
  return [
    for (final e in items)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
});

final stockAuditRecentHomeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: 8,
      );
});

/// Stock adjustments for a single calendar day (legacy / stock detail).
final stockAuditDayProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DateTime>((ref, day) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final d = DateTime(day.year, day.month, day.day);
  return ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: 50,
        on: _apiDate(d),
      );
});

/// Stock adjustments for the global [homePeriodProvider] window (client-filtered).
final stockAuditPeriodProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  final rows = await ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: 80,
      );
  return _filterAuditsToHomePeriod(ref, rows);
});

/// Period-scoped overview for category pills (reuses dashboard cache when possible).
final homeOwnerPeriodDashboardProvider =
    Provider.autoDispose<HomeDashboardData>((ref) {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) {
    return HomeDashboardData.empty;
  }
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  return ref.watch(homeDashboardDataProvider).snapshot.data;
});

final stockVariancesTodayProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockVariancesToday(
        businessId: session.primaryBusiness.id,
      );
});

final activeStaffSessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listActiveSessions(
        businessId: session.primaryBusiness.id,
      );
});

final activeSessionsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final rows = await ref.watch(activeStaffSessionsProvider.future);
  return rows.length;
});

/// Rolling calendar month (1st → today) for owner home quick stats.
final homeMonthDashboardDataProvider =
    FutureProvider.autoDispose<HomeDashboardData>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) {
    return HomeDashboardData.empty;
  }
  final session = ref.watch(sessionProvider);
  if (session == null) return HomeDashboardData.empty;
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month, now.day);
  final snap = await ref.read(hexaApiProvider).reportsHomeOverview(
        businessId: session.primaryBusiness.id,
        from: _apiDate(start),
        to: _apiDate(end),
        compact: true,
        shellBundle: false,
      );
  return homeDashboardDataFromApiSnapshot(HomePeriod.month, snap);
});

/// Unified owner feed: recent purchases + today's stock adjustments.
class HomeActivityItem {
  const HomeActivityItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.at,
    this.amountInr,
    this.routeId,
    this.actor,
    this.qtyChange,
  });

  final String kind; // purchase | stock
  final String title;
  final String subtitle;
  final DateTime at;
  final double? amountInr;
  final String? routeId;
  final String? actor;
  final String? qtyChange;
}

/// Group label + items for the recent-changes section.
class HomeActivityGroup {
  const HomeActivityGroup({required this.header, required this.items});

  final String header;
  final List<HomeActivityItem> items;
}

List<HomeActivityGroup> groupHomeActivityByDay(List<HomeActivityItem> items) {
  if (items.isEmpty) return [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 6));

  final todayList = <HomeActivityItem>[];
  final yesterdayList = <HomeActivityItem>[];
  final weekList = <HomeActivityItem>[];
  final olderList = <HomeActivityItem>[];

  for (final item in items) {
    final d = DateTime(item.at.year, item.at.month, item.at.day);
    if (!d.isBefore(today)) {
      todayList.add(item);
    } else if (!d.isBefore(yesterday)) {
      yesterdayList.add(item);
    } else if (!d.isBefore(weekStart)) {
      weekList.add(item);
    } else {
      olderList.add(item);
    }
  }

  final out = <HomeActivityGroup>[];
  if (todayList.isNotEmpty) {
    out.add(HomeActivityGroup(header: 'Today', items: todayList));
  }
  if (yesterdayList.isNotEmpty) {
    out.add(HomeActivityGroup(header: 'Yesterday', items: yesterdayList));
  }
  if (weekList.isNotEmpty) {
    out.add(HomeActivityGroup(header: 'This week', items: weekList));
  }
  if (olderList.isNotEmpty) {
    out.add(HomeActivityGroup(header: 'Earlier', items: olderList.take(8).toList()));
  }
  return out;
}

final homeRecentActivityFeedProvider =
    FutureProvider.autoDispose<List<HomeActivityItem>>((ref) async {
  if (!shellBranchIsVisible(ref, ShellBranch.home)) return [];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  final q = homeDateRangeForRef(ref);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final range = homePeriodRange(
    ref.read(homePeriodProvider),
    custom: ref.read(homeCustomDateRangeProvider),
  );

  final purchases = await api.listTradePurchases(
    businessId: bid,
    limit: 24,
    offset: 0,
    status: 'all',
    purchaseFrom: q.from,
    purchaseTo: q.to,
  );
  final auditRows = await api.listStockAuditRecent(
    businessId: bid,
    limit: 80,
  );
  final audits = _filterAuditsToHomePeriod(ref, auditRows);
  final items = <HomeActivityItem>[];

  for (final p in purchases) {
    final id = p['id']?.toString() ?? '';
    final atRaw = p['purchase_date']?.toString() ?? p['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    final local = at.toLocal();
    if (local.isBefore(range.start) || !local.isBefore(range.end)) continue;
    items.add(
      HomeActivityItem(
        kind: 'purchase',
        title: 'Purchase added',
        subtitle: p['supplier_name']?.toString() ??
            p['human_id']?.toString() ??
            p['invoice_number']?.toString() ??
            'Purchase',
        actor: p['created_by_name']?.toString() ??
            p['staff_name']?.toString() ??
            p['user_name']?.toString(),
        qtyChange: p['human_id']?.toString() ??
            p['invoice_number']?.toString() ??
            p['bill_no']?.toString() ??
            '',
        at: local,
        amountInr: coerceToDouble(p['total_amount'] ?? p['bill_total']),
        routeId: id.isNotEmpty ? id : null,
      ),
    );
  }

  for (final a in audits) {
    final atRaw = a['created_at']?.toString() ?? a['at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    final itemName = a['item_name']?.toString() ?? 'Item';
    final delta = a['delta_qty'] ?? a['qty_change'] ?? a['change'];
    items.add(
      HomeActivityItem(
        kind: 'stock',
        title: itemName,
        subtitle: 'Stock changed',
        at: at.toLocal(),
        routeId: a['item_id']?.toString(),
        actor: a['updated_by']?.toString() ??
            a['updated_by_name']?.toString() ??
            a['user_name']?.toString(),
        qtyChange: delta?.toString(),
      ),
    );
  }

  items.sort((a, b) => b.at.compareTo(a.at));
  return items.take(12).toList();
});

/// @deprecated Use [homeRecentActivityFeedProvider] only — kept for invalidation parity.
final homeRecentPurchasesCompactProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final q = homeDateRangeForRef(ref);
  final rows = await ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 6,
        offset: 0,
        status: 'all',
        purchaseFrom: q.from,
        purchaseTo: q.to,
      );
  return rows;
});
