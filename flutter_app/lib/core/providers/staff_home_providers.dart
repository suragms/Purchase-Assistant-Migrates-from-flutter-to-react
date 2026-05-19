import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/session.dart';
import 'barcode_recent_scans.dart';

/// Clears staff home caches after login/logout so a prior `session == null`
/// fetch never sticks as an empty list for the next user.
void invalidateStaffHomeCaches(Ref ref) {
  ref.invalidate(staffDisplayNameProvider);
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffLowStockAlertsProvider);
  ref.invalidate(staffRecentScansProvider);
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
  });

  final int scanned;
  final int stockUpdates;
  final int itemsCreated;
  final int verifications;
  final int purchases;

  int get total =>
      scanned + stockUpdates + itemsCreated + verifications + purchases;
}

StaffTodayActivitySummary summarizeStaffActivity(List<Map<String, dynamic>> rows) {
  var scan = 0;
  var stock = 0;
  var create = 0;
  var verify = 0;
  var purchases = 0;
  for (final r in rows) {
    final a = (r['action_type'] ?? r['action'] ?? '').toString().toUpperCase();
    if (a.contains('SCAN')) {
      scan++;
    } else if (a.contains('STOCK')) {
      stock++;
    } else if (a.contains('ITEM') && a.contains('CREATE')) {
      create++;
    } else if (a.contains('VERIF')) {
      verify++;
    } else if (a.contains('PURCHASE')) {
      purchases++;
    }
  }
  return StaffTodayActivitySummary(
    scanned: scan,
    stockUpdates: stock,
    itemsCreated: create,
    verifications: verify,
    purchases: purchases,
  );
}

final staffTodaySummaryProvider =
    Provider.autoDispose<AsyncValue<StaffTodayActivitySummary>>((ref) {
  return ref.watch(staffTodayActivityProvider).whenData(summarizeStaffActivity);
});
