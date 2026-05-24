import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/session.dart';
import '../models/trade_purchase_models.dart';
import 'barcode_recent_scans.dart';
import 'trade_purchases_provider.dart';

/// Clears staff home caches after login/logout so a prior `session == null`
/// fetch never sticks as an empty list for the next user.
void invalidateStaffHomeCaches(Ref ref) {
  ref.invalidate(staffDisplayNameProvider);
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffTodayStockWorkProvider);
  ref.invalidate(staffLowStockAlertsProvider);
  ref.invalidate(staffRecentScansProvider);
  ref.invalidate(missingCodeItemsProvider);
  ref.invalidate(tradePurchasesListProvider);
}

String _todayApiDate() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

final staffDisplayNameProvider = FutureProvider.autoDispose<String>((ref) async {
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
  final session = await _waitForSession(ref);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listActivityLog(
        businessId: session.primaryBusiness.id,
        period: 'today',
        page: 1,
        perPage: 80,
      );
});

/// Today's stock adjustments from audit feed (authoritative for stock work counts).
final staffTodayStockWorkProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await _waitForSession(ref);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockAuditFeed(
        businessId: session.primaryBusiness.id,
        onDate: _todayApiDate(),
        limit: 200,
      );
});

final staffLowStockAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = await _waitForSession(ref);
  if (session == null) return [];
  final m = await ref.read(hexaApiProvider).listStock(
        businessId: session.primaryBusiness.id,
        page: 1,
        perPage: 8,
        status: 'low',
      );
  final items = m['items'];
  if (items is! List) return [];
  return [
    for (final e in items)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
});

/// Undelivered trade purchases visible to staff (for home alert pill).
final staffPendingDeliveryCountProvider = Provider.autoDispose<int>((ref) {
  final purchases = ref.watch(staffPendingDeliveriesProvider).valueOrNull;
  return purchases?.length ?? 0;
});

/// Pending warehouse deliveries — oldest purchase date first.
final staffPendingDeliveriesProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  final list = ref.watch(tradePurchasesParsedProvider);
  return list.whenData((purchases) {
    final pending = purchases.where((p) => !p.isDelivered).toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    return pending;
  });
});

/// Last barcode scans from device prefs (shared with [BarcodeScanPage]).
final staffRecentScansProvider =
    FutureProvider.autoDispose<List<BarcodeRecentScan>>((ref) async {
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
  final session = await _waitForSession(ref);
  if (session == null) return [];
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
});

/// All catalog stock rows with empty item_code (paged load).
final missingCodeItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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
