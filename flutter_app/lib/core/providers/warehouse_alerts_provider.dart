import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../json_coerce.dart';
import 'stock_providers.dart' show providerKeepAlive;

/// Consolidated warehouse alert counts for home / stock LIVE chips.
class WarehouseAlerts {
  const WarehouseAlerts({
    this.pendingDeliveries = 0,
    this.lowStock = 0,
    this.criticalStock = 0,
    this.pendingVerifications = 0,
    this.missingBarcode = 0,
    this.missingUsageLogs = 0,
    this.evictionCount = 0,
    this.checklistCompletionPct = 100,
  });

  final int pendingDeliveries;
  final int lowStock;
  final int criticalStock;
  final int pendingVerifications;
  final int missingBarcode;
  final int missingUsageLogs;
  final int evictionCount;
  final double checklistCompletionPct;

  bool get incompleteChecklist => checklistCompletionPct < 100;

  bool get hasAny =>
      pendingDeliveries > 0 ||
      lowStock > 0 ||
      criticalStock > 0 ||
      pendingVerifications > 0 ||
      missingBarcode > 0 ||
      missingUsageLogs > 0 ||
      evictionCount > 0 ||
      incompleteChecklist;

  int get total =>
      pendingDeliveries +
      lowStock +
      criticalStock +
      pendingVerifications +
      missingBarcode +
      missingUsageLogs +
      evictionCount;
}

final warehouseAlertsProvider =
    FutureProvider.autoDispose<WarehouseAlerts>((ref) async {
  providerKeepAlive(ref, const Duration(seconds: 60));
  if (providerSkipApi(ref)) return const WarehouseAlerts();
  final session = ref.watch(activeSessionProvider);
  if (session == null) return const WarehouseAlerts();
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  Map<String, dynamic> summary = {};
  try {
    summary = await api.getWarehouseAlertsSummary(businessId: bid);
  } catch (_) {}
  return WarehouseAlerts(
    pendingDeliveries: coerceToInt(summary['pending_deliveries']),
    lowStock: coerceToInt(summary['low_stock']),
    criticalStock: coerceToInt(summary['critical_stock']),
    pendingVerifications: coerceToInt(summary['pending_verifications']),
    missingBarcode: coerceToInt(summary['missing_barcode']),
    missingUsageLogs: coerceToInt(summary['missing_usage_logs']),
    evictionCount: coerceToInt(summary['eviction_count']),
    checklistCompletionPct:
        coerceToDoubleNullable(summary['checklist_completion_pct']) ?? 100,
  );
});
