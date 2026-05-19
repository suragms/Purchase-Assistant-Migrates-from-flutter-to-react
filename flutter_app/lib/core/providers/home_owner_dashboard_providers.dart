import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import 'home_dashboard_provider.dart';

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Today-only dashboard row for the owner home stats strip (not tied to [homePeriodProvider]).
final homeTodayDashboardDataProvider =
    FutureProvider.autoDispose<HomeDashboardData>((ref) async {
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

/// Stock adjustments for a single calendar day (owner today feed).
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

final stockVariancesTodayProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockVariancesToday(
        businessId: session.primaryBusiness.id,
      );
});

final activeStaffSessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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
  });

  final String kind; // purchase | stock
  final String title;
  final String subtitle;
  final DateTime at;
  final double? amountInr;
  final String? routeId;
}

final homeRecentActivityFeedProvider =
    FutureProvider.autoDispose<List<HomeActivityItem>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);

  final purchases = await api.listTradePurchases(
    businessId: bid,
    limit: 8,
    offset: 0,
    status: 'all',
  );
  final audits = await api.listStockAuditRecent(
    businessId: bid,
    limit: 8,
    on: _apiDate(day),
  );
  final items = <HomeActivityItem>[];

  for (final p in purchases) {
    final id = p['id']?.toString() ?? '';
    final atRaw = p['purchase_date']?.toString() ?? p['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    items.add(
      HomeActivityItem(
        kind: 'purchase',
        title: p['supplier_name']?.toString() ??
            p['human_id']?.toString() ??
            'Purchase',
        subtitle: p['human_id']?.toString() ?? p['bill_no']?.toString() ?? '',
        at: at.toLocal(),
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
        subtitle: delta != null ? 'Stock ${delta.toString()}' : 'Stock updated',
        at: at.toLocal(),
        routeId: a['item_id']?.toString(),
      ),
    );
  }

  items.sort((a, b) => b.at.compareTo(a.at));
  return items.take(5).toList();
});

final homeRecentPurchasesCompactProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final from = _apiDate(day);
  final rows = await ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 6,
        offset: 0,
        status: 'all',
        purchaseFrom: from,
        purchaseTo: from,
      );
  return rows;
});
