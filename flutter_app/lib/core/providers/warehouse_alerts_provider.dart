import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

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
  final session = ref.watch(sessionProvider);
  if (session == null) return const WarehouseAlerts();
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  Map<String, dynamic> summary = {};
  try {
    summary = await api.getWarehouseAlertsSummary(businessId: bid);
  } catch (_) {}
  return WarehouseAlerts(
    pendingDeliveries: (summary['pending_deliveries'] as num?)?.toInt() ?? 0,
    lowStock: (summary['low_stock'] as num?)?.toInt() ?? 0,
    criticalStock: (summary['critical_stock'] as num?)?.toInt() ?? 0,
    pendingVerifications: (summary['pending_verifications'] as num?)?.toInt() ?? 0,
    missingBarcode: (summary['missing_barcode'] as num?)?.toInt() ?? 0,
    missingUsageLogs: (summary['missing_usage_logs'] as num?)?.toInt() ?? 0,
    evictionCount: (summary['eviction_count'] as num?)?.toInt() ?? 0,
    checklistCompletionPct:
        (summary['checklist_completion_pct'] as num?)?.toDouble() ?? 100,
  );
});
