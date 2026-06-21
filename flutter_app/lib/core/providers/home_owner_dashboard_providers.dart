import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../json_coerce.dart';
import '../utils/stock_audit_rows.dart';
import '../utils/home_activity_units.dart';
import 'stock_providers.dart'
    show lowStockByCategoryProvider, stockStatusCountsProvider;
import 'home_breakdown_tab_providers.dart';
import 'home_dashboard_provider.dart'
    show
        homeActivityFeedFetchEnabledProvider,
        homeDashboardDataProvider,
        homeOverviewReadyForSatellites,
        homeTabHasOperationalBundle,
        homePeriodProvider,
        homeCustomDateRangeProvider,
        homeStockMovementSectionVisibleProvider,
        homeLowStockTopFetchEnabledProvider,
        homeStaffSessionsFetchEnabledProvider,
        HomeDashboardData,
        homePeriodRange;
import 'api_read_snapshots.dart';
import 'delivery_pipeline_provider.dart';
import 'notifications_provider.dart' show mergedNotificationFeedProvider;
import 'warehouse_alerts_provider.dart';

String? _activityUnitsOrNull(String? raw) {
  final u = dedupeActivityUnitsLine(raw);
  return u.isEmpty ? null : u;
}

List<Map<String, dynamic>> _filterAuditsToHomePeriod(
  Ref ref,
  List<Map<String, dynamic>> rows,
) {
  return filterStockAuditRowsByHomePeriod(
    rows,
    ref.read(homePeriodProvider),
    custom: ref.read(homeCustomDateRangeProvider),
  );
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
  final disposed = registerProviderDisposeGuard(ref);
  final dashState = ref.watch(homeDashboardDataProvider);
  final inHand = dashState.snapshot.data.stockInHand;
  if (homeTabHasOperationalBundle(ref) && inHand != null) {
    return HomeInventorySummary(
      totalValueInr: inHand.totalValueInr,
      bags: inHand.bags,
      boxes: inHand.boxes,
      tins: inHand.tins,
      kg: inHand.kg,
      itemCount: inHand.itemCount,
    );
  }
  if (dashState.refreshing && !homeTabHasOperationalBundle(ref)) {
    return HomeInventorySummary.empty;
  }
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 5));
  final session = ref.watch(activeSessionProvider);
  if (session == null) return HomeInventorySummary.empty;
  try {
    final raw = await ref
        .read(hexaApiProvider)
        .stockInventorySummary(
          businessId: session.primaryBusiness.id,
        )
        .timeout(const Duration(seconds: 12));
    if (providerWasDisposed(disposed)) return HomeInventorySummary.empty;
    return HomeInventorySummary.fromJson(raw);
  } catch (_) {
    return HomeInventorySummary.empty;
  }
});

/// Single parallel fetch for low + critical counts (avoids duplicate sequential home polls).
final stockAlertCountsProvider =
    FutureProvider.autoDispose<({int low, int critical})>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final counts = await ref.watch(stockStatusCountsProvider.future);
  if (providerWasDisposed(disposed)) return (low: 0, critical: 0);
  return (
    low: coerceToInt(counts['low']),
    critical: coerceToInt(counts['critical']),
  );
});

final stockLowCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final c = await ref.watch(stockAlertCountsProvider.future);
  if (providerWasDisposed(disposed)) return 0;
  return c.low;
});

final stockCriticalCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final c = await ref.watch(stockAlertCountsProvider.future);
  if (providerWasDisposed(disposed)) return 0;
  return c.critical;
});

/// Items needing attention on home live bar (bundled stock_status_counts when on Home).
final homeStockAttentionCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  if (homeTabHasOperationalBundle(ref)) {
    return ref
        .watch(homeDashboardDataProvider)
        .snapshot
        .data
        .operational!
        .stockAttentionCount;
  }
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final counts = await ref.watch(stockStatusCountsProvider.future);
  if (providerWasDisposed(disposed)) return 0;
  final out = coerceToInt(counts['out']);
  final low = coerceToInt(counts['low']);
  final critical = coerceToInt(counts['critical']);
  return out + low + critical;
});

/// Low-stock attention on Home — uses shell bundle; grouped API only on low-stock route.
final homeLowStockAttentionCountProvider = Provider.autoDispose<int>((ref) {
  if (homeTabHasOperationalBundle(ref)) {
    return ref
        .watch(homeDashboardDataProvider)
        .snapshot
        .data
        .operational!
        .stockAttentionCount;
  }
  return ref.watch(homeStockAttentionCountProvider).valueOrNull ?? 0;
});

/// Pending delivery: operational bundle + delivery pipeline (max of both).
final homePendingDeliveryCountProvider = Provider.autoDispose<int>((ref) {
  if (homeTabHasOperationalBundle(ref)) {
    final fromOperational = ref
            .watch(homeDashboardDataProvider)
            .snapshot
            .data
            .operational
            ?.warehouseAlerts
            .pendingDeliveries ??
        0;
    final fromPipeline = deliveryPipelinePendingCount(
      ref.watch(deliveryPipelineProvider).valueOrNull,
    );
    return fromOperational > fromPipeline ? fromOperational : fromPipeline;
  }
  final fromWarehouse =
      ref.watch(warehouseAlertsProvider).valueOrNull?.pendingDeliveries ?? 0;
  final fromPipeline = deliveryPipelinePendingCount(
    ref.watch(deliveryPipelineProvider).valueOrNull,
  );
  return fromWarehouse > fromPipeline ? fromWarehouse : fromPipeline;
});

/// Unread staff reorder requests (inform-owner flow).
final homeStaffReorderRequestCountProvider = Provider.autoDispose<int>((ref) {
  final feed = ref.watch(mergedNotificationFeedProvider);
  return feed
      .where((n) => !n.isRead && (n.serverKind ?? '') == 'reorder_request')
      .length;
});

/// Bust home stock status sheet sources (call before opening sheet).
void invalidateHomeStockStatusCounts(Ref ref) {
  ref.invalidate(warehouseAlertsProvider);
  ref.invalidate(lowStockByCategoryProvider);
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(homeStockAttentionCountProvider);
}

/// Top low-stock rows (server sorts by stock vs reorder).
final stockLowTopHomeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!ref.watch(homeLowStockTopFetchEnabledProvider)) {
    return [];
  }
  if (homeTabHasOperationalBundle(ref)) {
    final bundled = ref
        .watch(homeDashboardDataProvider)
        .snapshot
        .data
        .operational
        ?.lowStockTop;
    if (bundled != null && bundled.isNotEmpty) {
      return bundled;
    }
  }
  if (!homeOverviewReadyForSatellites(ref)) {
    return [];
  }
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final m = await ref.read(hexaApiProvider).listStock(
        businessId: session.primaryBusiness.id,
        page: 1,
        perPage: 6,
        status: 'low',
        sort: 'stock_asc',
      );
  if (providerWasDisposed(disposed)) return [];
  final items = m['items'];
  if (items is! List) return [];
  return [
    for (final e in items)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
});

/// Stock adjustments for the global [homePeriodProvider] window (client-filtered).
final stockAuditPeriodProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  final rows = await ref.watch(stockAuditRecentSnapshotProvider.future);
  if (providerWasDisposed(disposed)) return [];
  return _filterAuditsToHomePeriod(ref, rows);
});
final stockAuditDayProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DateTime>((ref, day) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final d = DateTime(day.year, day.month, day.day);
  final bid = session.primaryBusiness.id;
  final api = ref.read(hexaApiProvider);
  final dayStr = _apiDate(d);
  final results = await Future.wait([
    ref.watch(stockAuditRecentSnapshotProvider.future),
    api.listTradePurchases(
      businessId: bid,
      limit: 40,
      offset: 0,
      status: 'all',
      purchaseFrom: dayStr,
      purchaseTo: dayStr,
    ),
  ]);
  if (providerWasDisposed(disposed)) return [];
  final auditRows = (results[0] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final audits = filterStockAuditRowsOnLocalDay(auditRows, d);
  final purchases = mapPurchasesToStockAuditRows(
    (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
  );
  final billsToday = filterStockAuditRowsOnLocalDay(purchases, d);
  return sortStockAuditRowsNewestFirst([...audits, ...billsToday]);
});

/// Period-scoped overview for category pills (reuses dashboard cache when possible).
final homeOwnerPeriodDashboardProvider =
    Provider.autoDispose<HomeDashboardData>((ref) {
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  return ref.watch(homeDashboardDataProvider).snapshot.data;
});

final stockVariancesTodayProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (homeTabHasOperationalBundle(ref)) {
    return const [];
  }
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      !ref.watch(homeStockMovementSectionVisibleProvider)) {
    return const [];
  }
  if (!shellBranchIsVisible(ref, ShellBranch.home) &&
      !shellBranchIsVisible(ref, ShellBranch.reports)) {
    return [];
  }
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final rows = await ref.read(hexaApiProvider).listStockVariancesToday(
        businessId: session.primaryBusiness.id,
      );
  if (providerWasDisposed(disposed)) return [];
  return rows;
});

final activeStaffSessionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      !ref.watch(homeStaffSessionsFetchEnabledProvider)) {
    return [];
  }
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final rows = await ref.read(hexaApiProvider).listActiveSessions(
        businessId: session.primaryBusiness.id,
      );
  if (providerWasDisposed(disposed)) return [];
  return rows;
});

final activeSessionsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final rows = await ref.watch(activeStaffSessionsProvider.future);
  if (providerWasDisposed(disposed)) return 0;
  return rows.length;
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
    this.createdBy,
    this.qtyChange,
    this.humanId,
    this.unitsLine,
    this.verifiedBy,
    this.supplierName,
  });

  final String kind; // purchase | stock
  final String title;
  final String subtitle;
  final DateTime at;
  final double? amountInr;
  final String? routeId;
  /// Who saved / scanned (staff or owner).
  final String? actor;
  /// Purchase bill creator (owner/admin/staff).
  final String? createdBy;
  final String? qtyChange;
  final String? humanId;
  final String? unitsLine;
  final String? verifiedBy;
  final String? supplierName;

  bool get isPurchaseDelivery =>
      kind == 'delivery_verified' ||
      title.startsWith('Delivery committed');

  HomeActivityItem copyWith({
    String? kind,
    String? title,
    String? subtitle,
    DateTime? at,
    double? amountInr,
    String? routeId,
    String? actor,
    String? createdBy,
    String? qtyChange,
    String? humanId,
    String? unitsLine,
    String? verifiedBy,
    String? supplierName,
  }) {
    return HomeActivityItem(
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      at: at ?? this.at,
      amountInr: amountInr ?? this.amountInr,
      routeId: routeId ?? this.routeId,
      actor: actor ?? this.actor,
      createdBy: createdBy ?? this.createdBy,
      qtyChange: qtyChange ?? this.qtyChange,
      humanId: humanId ?? this.humanId,
      unitsLine: unitsLine ?? this.unitsLine,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      supplierName: supplierName ?? this.supplierName,
    );
  }
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

String _activityKindFromAdjustment(String? adjustmentType) {
  final t = (adjustmentType ?? '').toLowerCase();
  if (t.contains('physical') || t.contains('count')) return 'physical_count';
  if (t.contains('opening')) return 'opening_stock_set';
  if (t.contains('correct')) return 'stock_correction';
  if (t.contains('damage')) return 'damage';
  if (t.contains('reorder')) return 'reorder_created';
  return 'stock';
}

String _activityTitleFromAdjustment(String? adjustmentType, String itemName) {
  final t = (adjustmentType ?? '').toLowerCase();
  if (t.contains('physical') || t.contains('count')) {
    return 'Physical stock updated';
  }
  if (t.contains('opening')) return 'Opening stock set';
  if (t.contains('correct')) return 'Stock corrected';
  if (t.contains('damage')) return 'Damage recorded';
  if (t.contains('reorder')) return 'Reorder logged';
  return itemName;
}

/// Parses audit reason `Purchase received ({human_id})` from delivery commit.
({String humanId, String? purchaseId})? _parsePurchaseReceivedReason(
  Map<String, dynamic> audit,
) {
  final reason = audit['reason']?.toString().trim() ?? '';
  final match = RegExp(r'^Purchase received \((.+)\)$').firstMatch(reason);
  if (match == null) return null;
  final humanId = match.group(1)?.trim() ?? '';
  if (humanId.isEmpty) return null;
  final meta = audit['metadata'];
  String? purchaseId;
  if (meta is Map) {
    purchaseId = meta['purchase_id']?.toString();
  }
  purchaseId ??= audit['source_id']?.toString() ?? audit['purchase_id']?.toString();
  return (humanId: humanId, purchaseId: purchaseId);
}

String? _purchaseCreatedBy(Map<String, dynamic> p) {
  for (final key in ['created_by_name', 'user_name', 'staff_name']) {
    final v = p[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

String? _purchaseVerifiedBy(Map<String, dynamic> p) {
  final v = p['staff_verified_by_name']?.toString().trim();
  if (v != null && v.isNotEmpty) return v;
  final notes = p['delivery_notes']?.toString() ?? '';
  final fromNotes = RegExp(
    r'Verified by ([^|\n]+)',
    caseSensitive: false,
  ).firstMatch(notes);
  if (fromNotes != null) {
    final name = fromNotes.group(1)?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

int _purchaseActivityIndex(
  List<HomeActivityItem> items, {
  String? purchaseId,
  String? humanId,
}) {
  if (purchaseId != null && purchaseId.isNotEmpty) {
    final byId = items.indexWhere((i) => i.routeId == purchaseId);
    if (byId >= 0) return byId;
  }
  final hid = humanId?.trim();
  if (hid == null || hid.isEmpty) return -1;
  return items.indexWhere(
    (i) =>
        i.humanId == hid &&
        (i.kind == 'purchase' || i.kind == 'delivery_verified'),
  );
}

void _enrichPurchaseActivityFromAudit(
  List<HomeActivityItem> items,
  String purchaseId,
  Map<String, dynamic> audit, {
  String? humanId,
}) {
  final idx = _purchaseActivityIndex(
    items,
    purchaseId: purchaseId,
    humanId: humanId,
  );
  if (idx < 0) return;
  final existing = items[idx];
  final verified = audit['updated_by_name']?.toString().trim();
  final units = stockAuditActivityUnitsLine(audit);
  final mergedUnits = dedupeActivityUnitsLine(
    existing.unitsLine?.trim().isNotEmpty == true ? existing.unitsLine : units,
  );
  items[idx] = existing.copyWith(
    verifiedBy: (existing.verifiedBy?.trim().isNotEmpty == true)
        ? existing.verifiedBy
        : (verified != null && verified.isNotEmpty ? verified : null),
    unitsLine: mergedUnits.isNotEmpty ? mergedUnits : null,
  );
}

HomeActivityItem _mergeDeliveryActivityGroup(List<HomeActivityItem> group) {
  if (group.length == 1) {
    final only = group.single;
    final units = dedupeActivityUnitsLine(only.unitsLine);
    return units.isEmpty ? only : only.copyWith(unitsLine: units);
  }
  group.sort((a, b) => b.at.compareTo(a.at));
  var best = group.first;
  for (final g in group) {
    if (warehouseActivityRowScore(
          unitsLine: g.unitsLine,
          verifiedBy: g.verifiedBy,
          amountInr: g.amountInr,
          supplierName: g.supplierName,
        ) >
        warehouseActivityRowScore(
          unitsLine: best.unitsLine,
          verifiedBy: best.verifiedBy,
          amountInr: best.amountInr,
          supplierName: best.supplierName,
        )) {
      best = g;
    }
  }
  String? bestUnits;
  var unitsScore = -1;
  for (final g in group) {
    final u = g.unitsLine?.trim();
    if (u == null || u.isEmpty) continue;
    final score = activityUnitsLineQualityScore(u);
    if (score > unitsScore) {
      unitsScore = score;
      bestUnits = u;
    }
  }
  var verifiedBy = best.verifiedBy?.trim();
  var createdBy = best.createdBy?.trim();
  var supplierName = best.supplierName?.trim();
  double? amountInr = best.amountInr;
  for (final g in group) {
    final v = g.verifiedBy?.trim();
    if ((verifiedBy == null || verifiedBy.isEmpty) &&
        v != null &&
        v.isNotEmpty) {
      verifiedBy = v;
    }
    final c = g.createdBy?.trim() ?? g.actor?.trim();
    if ((createdBy == null || createdBy.isEmpty) &&
        c != null &&
        c.isNotEmpty) {
      createdBy = c;
    }
    final s = g.supplierName?.trim();
    if ((supplierName == null || supplierName.isEmpty) &&
        s != null &&
        s.isNotEmpty) {
      supplierName = s;
    }
    final a = g.amountInr;
    if ((amountInr == null || amountInr <= 0) && a != null && a > 0) {
      amountInr = a;
    }
  }
  final units = dedupeActivityUnitsLine(bestUnits ?? best.unitsLine);
  return best.copyWith(
    unitsLine: units.isNotEmpty ? units : best.unitsLine,
    verifiedBy: verifiedBy?.isNotEmpty == true ? verifiedBy : best.verifiedBy,
    createdBy: createdBy?.isNotEmpty == true ? createdBy : best.createdBy,
    supplierName:
        supplierName?.isNotEmpty == true ? supplierName : best.supplierName,
    amountInr: amountInr ?? best.amountInr,
  );
}

List<HomeActivityItem> _collapseDuplicateDeliveryActivity(
  List<HomeActivityItem> items,
) {
  final out = <HomeActivityItem>[];
  final deliveryGroups = <String, List<HomeActivityItem>>{};
  for (final i in items) {
    final hid = i.humanId?.trim();
    if (i.kind == 'delivery_verified' &&
        hid != null &&
        hid.isNotEmpty) {
      deliveryGroups.putIfAbsent(hid, () => []).add(i);
    } else {
      out.add(i);
    }
  }
  for (final group in deliveryGroups.values) {
    out.add(_mergeDeliveryActivityGroup(group));
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

Future<List<HomeActivityItem>> _fetchHomeWarehouseActivity(
  Ref ref, {
  int purchaseLimit = 15,
  int maxItems = 15,
  Duration feedTimeout = const Duration(seconds: 15),
}) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 5));
  // Period drives refetch; do not watch session — resume JWT refresh must not
  // cancel/restart this fetch (caused infinite skeletons on Warehouse activity).
  final session = ref.read(activeSessionProvider);
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

  late final List<Map<String, dynamic>> purchases;
  late final List<Map<String, dynamic>> auditRows;
  late final List<Map<String, dynamic>> staffPurchases;
  try {
    final auditFuture = ref.read(stockAuditRecentSnapshotProvider.future);
    final results = await Future.wait<dynamic>([
      api.listTradePurchases(
        businessId: bid,
        limit: purchaseLimit,
        offset: 0,
        status: 'all',
        purchaseFrom: q.from,
        purchaseTo: q.to,
      ),
      auditFuture,
      api.listStaffPurchaseLogs(
        businessId: bid,
        limit: 30,
      ),
    ]).timeout(feedTimeout);
    purchases = List<Map<String, dynamic>>.from(results[0] as List);
    auditRows = (results[1] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    staffPurchases = List<Map<String, dynamic>>.from(results[2] as List);
  } on TimeoutException {
    throw Exception('Recent changes timed out. Pull to refresh.');
  }
  if (providerWasDisposed(disposed)) return [];
  final audits = _filterAuditsToHomePeriod(ref, auditRows);
  final items = <HomeActivityItem>[];
  final seenPurchaseIds = <String>{};

  for (final p in purchases) {
    final id = p['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      if (seenPurchaseIds.contains(id)) continue;
      seenPurchaseIds.add(id);
    }
    final atRaw = p['purchase_date']?.toString() ?? p['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    final local = at.toLocal();
    if (local.isBefore(range.start) || !local.isBefore(range.end)) continue;
    final deliveryStatus =
        (p['delivery_status'] ?? '').toString().toLowerCase();
    final delivered = p['is_delivered'] == true ||
        deliveryStatus == 'stock_committed';
    items.add(
      HomeActivityItem(
        kind: delivered ? 'delivery_verified' : 'purchase',
        title: delivered ? 'Delivery verified' : 'Purchase bill added',
        subtitle: p['supplier_name']?.toString() ??
            p['human_id']?.toString() ??
            p['invoice_number']?.toString() ??
            'Purchase',
        actor: _purchaseCreatedBy(p),
        createdBy: _purchaseCreatedBy(p),
        humanId: p['human_id']?.toString(),
        unitsLine: _activityUnitsOrNull(purchaseActivityUnitsLine(p)),
        verifiedBy: delivered ? _purchaseVerifiedBy(p) : null,
        supplierName: p['supplier_name']?.toString(),
        at: local,
        amountInr: coerceToDouble(p['total_amount'] ?? p['bill_total']),
        routeId: id.isNotEmpty ? id : null,
      ),
    );
  }

  for (final a in audits) {
    final atRaw = a['created_at']?.toString() ?? a['at']?.toString() ?? a['updated_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    final local = at.toLocal();
    if (local.isBefore(range.start) || !local.isBefore(range.end)) continue;
    final itemName = a['item_name']?.toString() ?? 'Item';
    final adjType = a['adjustment_type']?.toString();
    final received = _parsePurchaseReceivedReason(a);
    final purchaseId = received?.purchaseId?.trim();
    if (received != null) {
      final pid = purchaseId?.trim() ?? '';
      final hid = received.humanId.trim();
      final linked = (pid.isNotEmpty && seenPurchaseIds.contains(pid)) ||
          (hid.isNotEmpty &&
              _purchaseActivityIndex(items, humanId: hid) >= 0);
      if (linked) {
        _enrichPurchaseActivityFromAudit(
          items,
          pid,
          a,
          humanId: hid.isNotEmpty ? hid : null,
        );
        continue;
      }
    }
    final kind = received != null
        ? 'delivery_verified'
        : _activityKindFromAdjustment(adjType);
    final unitsLine = stockAuditActivityUnitsLine(a);
    items.add(
      HomeActivityItem(
        kind: kind,
        title: received != null
            ? 'Delivery committed — ${received.humanId}'
            : _activityTitleFromAdjustment(adjType, itemName),
        subtitle: itemName,
        humanId: received?.humanId,
        unitsLine: _activityUnitsOrNull(unitsLine),
        verifiedBy: a['updated_by_name']?.toString() ??
            a['updated_by']?.toString() ??
            a['user_name']?.toString(),
        at: local,
        routeId: received?.purchaseId?.isNotEmpty == true
            ? received!.purchaseId
            : a['item_id']?.toString(),
        actor: a['updated_by_name']?.toString() ??
            a['updated_by']?.toString() ??
            a['user_name']?.toString(),
        createdBy: a['updated_by_name']?.toString(),
      ),
    );
  }

  for (final p in staffPurchases) {
    final atRaw = p['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    final local = at.toLocal();
    if (local.isBefore(range.start) || !local.isBefore(range.end)) continue;
    final qty = coerceToDouble(p['qty']);
    final unit = p['unit']?.toString().toUpperCase() ?? '';
    items.add(
      HomeActivityItem(
        kind: 'stock_quick_purchase',
        title: 'Purchase quantity added',
        subtitle: p['item_name']?.toString() ?? 'Item',
        unitsLine: qty > 0 ? '+$qty $unit' : null,
        at: local,
        routeId: p['item_id']?.toString(),
        actor: p['created_by_name']?.toString(),
        qtyChange: qty > 0 ? '+$qty $unit' : null,
      ),
    );
  }

  const keepKinds = {
    'purchase',
    'delivery_verified',
    'stock_quick_purchase',
    'physical_count',
    'opening_stock_set',
    'stock_correction',
    'reorder_created',
  };
  items.removeWhere((i) => !keepKinds.contains(i.kind));

  final collapsed = _collapseDuplicateDeliveryActivity(items);
  return collapsed.take(maxItems).toList();
}

final homeRecentActivityFeedProvider =
    FutureProvider.autoDispose<List<HomeActivityItem>>((ref) async {
  if (!ref.watch(homeActivityFeedFetchEnabledProvider)) {
    return const [];
  }
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 30));
  ref.watch(homePeriodProvider);
  ref.watch(homeCustomDateRangeProvider);
  final items = await _fetchHomeWarehouseActivity(ref, purchaseLimit: 15, maxItems: 15);
  if (providerWasDisposed(disposed)) return const [];
  return items;
});

/// Full warehouse activity list for Home → View all (respects shared period).
///
/// Not autoDispose — avoids reload loops when Home stays mounted under
/// `/home/activity`. Pull-to-refresh or period change still refetches.
final homeWarehouseActivityFullProvider =
    FutureProvider<List<HomeActivityItem>>((ref) async {
  ref.keepAlive();
  return _fetchHomeWarehouseActivity(
    ref,
    purchaseLimit: 60,
    maxItems: 200,
    feedTimeout: const Duration(seconds: 30),
  );
});

/// @deprecated Use [homeRecentActivityFeedProvider] only — kept for invalidation parity.
final homeRecentPurchasesCompactProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final session = ref.watch(activeSessionProvider);
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
  if (providerWasDisposed(disposed)) return [];
  return rows;
});
