import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../auth/session_notifier.dart';
import '../models/session.dart';
import '../models/trade_purchase_models.dart';
import 'barcode_recent_scans.dart';
import 'delivery_pipeline_provider.dart';
import 'prefs_provider.dart';
import 'stock_providers.dart';
import 'trade_purchases_provider.dart';

void _providerKeepAlive(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  final timer = Timer(ttl, link.close);
  ref.onDispose(timer.cancel);
}

/// Clears staff home caches after login/logout so a prior `session == null`
/// fetch never sticks as an empty list for the next user.
void invalidateStaffHomeCaches(Ref ref) {
  ref.invalidate(staffDisplayNameProvider);
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffTodayStockWorkProvider);
  ref.invalidate(staffLowStockAlertsProvider);
  ref.invalidate(staffRecentScansProvider);
  ref.invalidate(staffRecentActivityProvider);
  ref.invalidate(staffStockMismatchCountProvider);
  ref.invalidate(missingCodeItemsProvider);
  ref.invalidate(staffTradePurchasesHistoryProvider);
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(openingStockMissingProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(stockOnHandTotalsProvider);
}

bool _staffSessionActive(Ref ref) {
  final session = ref.watch(sessionProvider);
  final authExpired = ref.watch(authSessionExpiredProvider);
  return session != null && !authExpired;
}

/// Floor role hint for staff home layout (client preference until API has staff_focus).
enum StaffHomeFocus { all, barcode, stock, purchase }

StaffHomeFocus staffHomeFocusFromStorage(String? raw) {
  return StaffHomeFocus.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => StaffHomeFocus.all,
  );
}

bool staffHomeShowsWarehouse(StaffHomeFocus f) =>
    f == StaffHomeFocus.all || f == StaffHomeFocus.stock;

bool staffHomeShowsBarcodeTools(StaffHomeFocus f) =>
    f == StaffHomeFocus.all || f == StaffHomeFocus.barcode;

bool staffHomeShowsPurchaseTools(StaffHomeFocus f) =>
    f == StaffHomeFocus.all || f == StaffHomeFocus.purchase;

class StaffHomeFocusNotifier extends Notifier<StaffHomeFocus> {
  static const _k = 'staff_home_focus';

  @override
  StaffHomeFocus build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_k);
    return staffHomeFocusFromStorage(raw);
  }

  Future<void> setFocus(StaffHomeFocus focus) async {
    await ref.read(sharedPreferencesProvider).setString(_k, focus.name);
    state = focus;
  }
}

final staffHomeFocusProvider =
    NotifierProvider<StaffHomeFocusNotifier, StaffHomeFocus>(
  StaffHomeFocusNotifier.new,
);

String _todayApiDate() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

final staffDisplayNameProvider = FutureProvider.autoDispose<String>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 5));
  final session = await _waitForSession(ref);
  if (session == null) return 'Staff';
  try {
    final p = await ref.read(hexaApiProvider).meProfile();
    for (final k in ['name', 'full_name', 'username']) {
      final v = p[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
  } catch (_) {}
  return 'Staff';
});

bool _isAuthFailure(Object e) {
  if (e is DioException) {
    final sc = e.response?.statusCode;
    return sc == 401 || sc == 403;
  }
  return false;
}

void _rethrowAuthFailure(Object e) {
  if (_isAuthFailure(e)) throw e;
}

Future<Session?> _waitForSession(Ref ref, {int attempts = 40}) async {
  var session = ref.watch(sessionProvider);
  if (session != null) return session;
  for (var i = 0; i < attempts; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    session = ref.read(sessionProvider);
    if (session != null) return session;
  }
  return ref.read(sessionProvider);
}

final staffTodayActivityProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  final session = await _waitForSession(ref);
  if (session == null) return [];
  try {
    return await ref.read(hexaApiProvider).listActivityLog(
          businessId: session.primaryBusiness.id,
          period: 'today',
          page: 1,
          perPage: 80,
        );
  } catch (e) {
    _rethrowAuthFailure(e);
    rethrow;
  }
});

/// Today's stock adjustments from audit feed (authoritative for stock work counts).
final staffTodayStockWorkProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  if (!_staffSessionActive(ref)) return [];
  final session = await _waitForSession(ref);
  if (session == null) return [];
  try {
    return await ref.read(hexaApiProvider).listStockAuditFeed(
          businessId: session.primaryBusiness.id,
          onDate: _todayApiDate(),
          limit: 200,
        );
  } catch (e) {
    _rethrowAuthFailure(e);
    rethrow;
  }
});

final staffLowStockAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  final session = await _waitForSession(ref);
  if (session == null) return [];
  try {
    final m = await ref.read(hexaApiProvider).listStockLow(
          businessId: session.primaryBusiness.id,
          page: 1,
          perPage: 8,
        );
    final items = m['items'];
    if (items is! List) return [];
    return [
      for (final e in items)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  } catch (e) {
    _rethrowAuthFailure(e);
    rethrow;
  }
});

/// Low + out count for staff home attention (fallback when low list is empty).
final staffLowStockAttentionCountProvider = Provider.autoDispose<int>((ref) {
  final alerts = ref.watch(staffLowStockAlertsProvider);
  final counts = ref.watch(stockStatusCountsProvider);
  return alerts.when(
    data: (rows) {
      if (rows.isNotEmpty) return rows.length;
      return counts.when(
        data: (c) => (c['low'] ?? 0) + (c['out'] ?? 0),
        loading: () => 0,
        error: (_, __) => 0,
      );
    },
    loading: () => counts.when(
      data: (c) => (c['low'] ?? 0) + (c['out'] ?? 0),
      loading: () => 0,
      error: (_, __) => 0,
    ),
    error: (_, __) => counts.when(
      data: (c) => (c['low'] ?? 0) + (c['out'] ?? 0),
      loading: () => 0,
      error: (_, __) => 0,
    ),
  );
});

/// Floor KPI counts from delivery pipeline API + stock status.
class StaffFloorKpis {
  const StaffFloorKpis({
    this.pending = 0,
    this.delivered = 0,
    this.lowStock = 0,
  });

  final int pending;
  final int delivered;
  final int lowStock;
}

int _pipelinePendingCount(Map<String, dynamic> p) =>
    deliveryPipelinePendingCount(p);

final staffDeliveryPipelineKpisProvider =
    Provider.autoDispose<AsyncValue<StaffFloorKpis>>((ref) {
  if (!_staffSessionActive(ref)) {
    return const AsyncData(StaffFloorKpis());
  }
  final pipeline = ref.watch(deliveryPipelineProvider);
  final low = ref.watch(staffLowStockAttentionCountProvider);
  return pipeline.when(
    data: (p) => AsyncData(
      StaffFloorKpis(
        pending: _pipelinePendingCount(p),
        delivered: (p['stock_committed'] as num?)?.toInt() ?? 0,
        lowStock: low,
      ),
    ),
    loading: () => const AsyncLoading(),
    error: (e, st) => AsyncError(e, st),
  );
});

/// Undelivered trade purchases visible to staff (for home alert pill).
final staffPendingDeliveryCountProvider = Provider.autoDispose<int>((ref) {
  final kpis = ref.watch(staffDeliveryPipelineKpisProvider);
  return kpis.valueOrNull?.pending ??
      ref.watch(staffPendingDeliveriesProvider).valueOrNull?.length ??
      0;
});

bool staffDeliveryNeedsAction(TradePurchase p) {
  if (p.statusEnum == PurchaseStatus.deleted ||
      p.statusEnum == PurchaseStatus.cancelled) {
    return false;
  }
  if (p.isDeliveryCommitted) return false;
  final ds = p.deliveryStatusEnum;
  if (ds == DeliveryStatus.pending ||
      ds == DeliveryStatus.dispatched ||
      ds == DeliveryStatus.inTransit ||
      ds == DeliveryStatus.arrived ||
      ds == DeliveryStatus.staffVerifying) {
    return true;
  }
  if (p.isDelivered) return true;
  return false;
}

/// Grouped delivery pipeline for staff deliveries page sections.
class StaffDeliverySections {
  const StaffDeliverySections({
    this.dispatched = const [],
    this.arrived = const [],
    this.pendingVerification = const [],
  });

  final List<TradePurchase> dispatched;
  final List<TradePurchase> arrived;
  final List<TradePurchase> pendingVerification;

  int get total =>
      dispatched.length + arrived.length + pendingVerification.length;
}

StaffDeliverySections groupStaffDeliverySections(List<TradePurchase> purchases) {
  final dispatched = <TradePurchase>[];
  final arrived = <TradePurchase>[];
  final pendingVerification = <TradePurchase>[];
  for (final p in purchases) {
    if (p.statusEnum == PurchaseStatus.deleted ||
        p.statusEnum == PurchaseStatus.cancelled ||
        p.isDeliveryCommitted) {
      continue;
    }
    final ds = p.deliveryStatusEnum;
    if (ds == DeliveryStatus.pending ||
        ds == DeliveryStatus.dispatched ||
        ds == DeliveryStatus.inTransit) {
      dispatched.add(p);
    } else if (ds == DeliveryStatus.staffVerified ||
        ds == DeliveryStatus.partial) {
      pendingVerification.add(p);
    } else if (ds == DeliveryStatus.arrived ||
        ds == DeliveryStatus.staffVerifying ||
        p.isDelivered ||
        staffDeliveryNeedsAction(p)) {
      arrived.add(p);
    }
  }
  int cmp(TradePurchase a, TradePurchase b) =>
      a.purchaseDate.compareTo(b.purchaseDate);
  dispatched.sort(cmp);
  arrived.sort(cmp);
  pendingVerification.sort(cmp);
  return StaffDeliverySections(
    dispatched: dispatched,
    arrived: arrived,
    pendingVerification: pendingVerification,
  );
}

final staffDeliverySectionsProvider =
    Provider.autoDispose<AsyncValue<StaffDeliverySections>>((ref) {
  final list = ref.watch(tradePurchasesForAlertsParsedProvider);
  return list.whenData(groupStaffDeliverySections);
});

/// Warehouse deliveries staff can act on (arrive / verify) — oldest first.
final staffPendingDeliveriesProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  final sections = ref.watch(staffDeliverySectionsProvider);
  return sections.whenData((s) {
    final pending = [...s.dispatched, ...s.arrived, ...s.pendingVerification];
    pending.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    return pending;
  });
});

/// Last barcode scans from device prefs (shared with [BarcodeScanPage]).
final staffRecentScansProvider =
    FutureProvider.autoDispose<List<BarcodeRecentScan>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 5));
  return loadBarcodeRecentScans(max: 8);
});

/// Counts for today's activity summary cards on staff home.
class StaffTodayActivitySummary {
  const StaffTodayActivitySummary({
    this.scanned = 0,
    this.stockUpdates = 0,
    this.itemsCreated = 0,
    this.verifications = 0,
    this.purchases = 0,
    this.itemsChecked = 0,
  });

  final int scanned;
  final int stockUpdates;
  final int itemsCreated;
  final int verifications;
  final int purchases;
  /// Unique items with a stock audit row today.
  final int itemsChecked;

  int get total =>
      scanned + stockUpdates + itemsCreated + verifications + purchases;
}

StaffTodayActivitySummary summarizeStaffToday({
  required List<Map<String, dynamic>> activityRows,
  required List<Map<String, dynamic>> auditRows,
}) {
  var scan = 0;
  var create = 0;
  var verify = 0;
  var purchases = 0;
  for (final r in activityRows) {
    final a = (r['action_type'] ?? r['action'] ?? '').toString().toUpperCase();
    if (a.contains('SCAN')) {
      scan++;
    } else if (a.contains('ITEM') && a.contains('CREATE')) {
      create++;
    } else if (a.contains('VERIF')) {
      verify++;
    } else if (a.contains('PURCHASE')) {
      purchases++;
    }
  }

  final itemIds = <String>{};
  for (final a in auditRows) {
    final id = a['item_id']?.toString() ?? '';
    if (id.isNotEmpty) itemIds.add(id);
  }

  return StaffTodayActivitySummary(
    scanned: scan,
    stockUpdates: auditRows.length,
    itemsCreated: create,
    verifications: verify,
    purchases: purchases,
    itemsChecked: itemIds.length,
  );
}

final staffTodaySummaryProvider =
    Provider.autoDispose<AsyncValue<StaffTodayActivitySummary>>((ref) {
  final activity = ref.watch(staffTodayActivityProvider);
  final audits = ref.watch(staffTodayStockWorkProvider);
  if (activity.isLoading || audits.isLoading) {
    return const AsyncLoading();
  }
  if (activity.hasError) return AsyncError(activity.error!, activity.stackTrace!);
  if (audits.hasError) return AsyncError(audits.error!, audits.stackTrace!);
  return AsyncData(
    summarizeStaffToday(
      activityRows: activity.valueOrNull ?? [],
      auditRows: audits.valueOrNull ?? [],
    ),
  );
});

final staffTodayPurchasesProvider = FutureProvider.autoDispose<List<TradePurchase>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  if (!_staffSessionActive(ref)) return [];
  final session = await _waitForSession(ref);
  if (session == null) return [];
  try {
    final today = _todayApiDate();
    final rows = await ref.read(hexaApiProvider).listTradePurchases(
          businessId: session.primaryBusiness.id,
          limit: 20,
          offset: 0,
          status: 'all',
          purchaseFrom: today,
          purchaseTo: today,
        );
    return [
      for (final e in rows)
        TradePurchase.fromJson(Map<String, dynamic>.from(e)),
    ];
  } catch (e) {
    _rethrowAuthFailure(e);
    rethrow;
  }
});

enum StaffPurchaseHistoryPeriod { today, week, allTime }

/// Staff purchase history — no financial fields (API redacts for staff role).
final staffTradePurchasesHistoryProvider = FutureProvider.autoDispose
    .family<List<TradePurchase>, StaffPurchaseHistoryPeriod>((ref, period) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  if (!_staffSessionActive(ref)) {
    throw StateError('Session expired — sign in again');
  }
  final session = await _waitForSession(ref);
  if (session == null) {
    throw StateError('Session expired — sign in again');
  }

  String? from;
  String? to;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case StaffPurchaseHistoryPeriod.today:
      from = _todayApiDate();
      to = from;
    case StaffPurchaseHistoryPeriod.week:
      final weekStart = today.subtract(Duration(days: today.weekday - 1));
      from = '${weekStart.year.toString().padLeft(4, '0')}-'
          '${weekStart.month.toString().padLeft(2, '0')}-'
          '${weekStart.day.toString().padLeft(2, '0')}';
      to = _todayApiDate();
    case StaffPurchaseHistoryPeriod.allTime:
      from = null;
      to = null;
  }

  try {
    const pageSize = 50;
    var offset = 0;
    const maxRows = 500;
    final raw = <Map<String, dynamic>>[];
    while (raw.length < maxRows) {
      final page = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: pageSize,
            offset: offset,
            purchaseFrom: from,
            purchaseTo: to,
          );
      if (page.isEmpty) break;
      raw.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    final parsed = <TradePurchase>[];
    for (final e in raw) {
      try {
        parsed.add(TradePurchase.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    parsed.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return parsed;
  } catch (e) {
    _rethrowAuthFailure(e);
    rethrow;
  }
});

/// All catalog stock rows with empty item_code (paged load).
final missingCodeItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  final session = await _waitForSession(ref);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  const pageSize = 500;
  var page = 1;
  final missing = <Map<String, dynamic>>[];
  while (page <= 40) {
    final res = await api.listStock(
      businessId: session.primaryBusiness.id,
      page: page,
      perPage: pageSize,
      status: 'all',
      sort: 'name',
    );
    final total = (res['total'] as num?)?.toInt() ?? 0;
    final raw = (res['items'] as List?) ?? const [];
    if (raw.isEmpty) break;
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final code = m['item_code']?.toString().trim() ?? '';
      if (code.isEmpty) missing.add(m);
    }
    if (page * pageSize >= total) break;
    page++;
  }
  return missing;
});

final staffMissingCodeCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(missingCodeItemsProvider).valueOrNull?.length ?? 0;
});

final staffOpeningStockCountProvider = Provider.autoDispose<int>((ref) {
  final m = ref.watch(openingStockMissingProvider).valueOrNull;
  return (m?['missing_count'] as num?)?.toInt() ?? 0;
});

final staffStockMismatchCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  final session = await _waitForSession(ref);
  if (session == null) return 0;
  final rows = await ref.read(hexaApiProvider).listStockVariancesToday(
        businessId: session.primaryBusiness.id,
      );
  return rows.length;
});

/// Unified recent actions for staff home (activity log + device scans).
class StaffRecentActivityItem {
  const StaffRecentActivityItem({
    required this.label,
    required this.when,
    this.subtitle,
    this.itemId,
    this.isScan = false,
  });

  final String label;
  final String? subtitle;
  final DateTime when;
  final String? itemId;
  final bool isScan;
}

String staffActivityLabel(String actionType) {
  switch (actionType.toUpperCase()) {
    case 'STAFF_LOGIN':
      return 'Signed in';
    case 'STAFF_LOGOUT':
      return 'Signed out';
    case 'PURCHASE_CREATE':
      return 'Purchase saved';
    case 'SCAN':
    case 'BARCODE_SCAN':
      return 'Barcode scan';
    default:
      return actionType.replaceAll('_', ' ');
  }
}

final staffRecentActivityProvider =
    FutureProvider.autoDispose<List<StaffRecentActivityItem>>((ref) async {
  _providerKeepAlive(ref, const Duration(minutes: 2));
  final activityRows = await ref.watch(staffTodayActivityProvider.future);
  final scans = await ref.watch(staffRecentScansProvider.future);
  final now = DateTime.now();
  final items = <StaffRecentActivityItem>[];

  for (final r in activityRows) {
    final actionRaw = (r['action_type'] ?? r['action'] ?? '').toString();
    DateTime when;
    try {
      when = DateTime.parse(r['created_at']?.toString() ?? '').toLocal();
    } catch (_) {
      when = now;
    }
    final itemName = r['item_name']?.toString();
    items.add(
      StaffRecentActivityItem(
        label: staffActivityLabel(actionRaw),
        subtitle: itemName?.trim().isNotEmpty == true ? itemName : null,
        when: when,
        itemId: r['item_id']?.toString(),
      ),
    );
  }

  for (final s in scans) {
    items.add(
      StaffRecentActivityItem(
        label: 'Barcode scan',
        subtitle: s.name.isNotEmpty ? s.name : s.code,
        when: now,
        itemId: s.id.isNotEmpty ? s.id : null,
        isScan: true,
      ),
    );
  }

  items.sort((a, b) => b.when.compareTo(a.when));
  return items.take(8).toList();
});
