import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../auth/provider_api_guard.dart';
import '../debug/agent_debug_log.dart';

int _dbgAuditRecentFetchCount = 0;

final Map<String, Future<List<Map<String, dynamic>>>> _tradePurchasesRecentInflight =
    {};
final Map<String, Future<List<Map<String, dynamic>>>> _auditRecentInflight = {};

/// SSOT for `GET …/stock/audit/recent` — one fetch serves home, stock tabs, and activity.
final stockAuditRecentSnapshotProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final keepAliveLink = ref.keepAlive();
  final keepAliveTimer = Timer(const Duration(minutes: 2), keepAliveLink.close);
  ref.onDispose(keepAliveTimer.cancel);
  if (providerSkipApi(ref)) return [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final bid = session.primaryBusiness.id;
  _dbgAuditRecentFetchCount++;
  // #region agent log
  agentDebugLog(
    hypothesisId: 'H5',
    location: 'api_read_snapshots.dart:auditRecent',
    message: 'audit recent fetch invoked',
    data: {'count': _dbgAuditRecentFetchCount},
  );
  // #endregion
  final rows = await _auditRecentInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .listStockAuditRecent(
          businessId: bid,
          limit: HexaApi.stockAuditRecentMaxLimit,
        )
        .whenComplete(() => _auditRecentInflight.remove(bid)),
  );
  return rows;
});

/// SSOT for recent unfiltered `GET …/trade-purchases?limit=50` (alerts + catalog intel).
final tradePurchasesRecentSnapshotProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (providerSkipApi(ref)) return [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final bid = session.primaryBusiness.id;
  final page = await _tradePurchasesRecentInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .listTradePurchases(businessId: bid, limit: 50)
        .whenComplete(() => _tradePurchasesRecentInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) return [];
  return page;
});

void bustStockAuditRecentSnapshot(dynamic ref) {
  ref.invalidate(stockAuditRecentSnapshotProvider);
}

void bustTradePurchasesRecentSnapshot(dynamic ref) {
  ref.invalidate(tradePurchasesRecentSnapshotProvider);
}
