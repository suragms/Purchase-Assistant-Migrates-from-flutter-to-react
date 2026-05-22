import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'home_owner_dashboard_providers.dart';

/// Consolidated warehouse alert counts for home / stock LIVE chips.
class WarehouseAlerts {
  const WarehouseAlerts({
    this.pendingDeliveries = 0,
    this.lowStock = 0,
    this.criticalStock = 0,
    this.pendingVerifications = 0,
  });

  final int pendingDeliveries;
  final int lowStock;
  final int criticalStock;
  final int pendingVerifications;

  int get total =>
      pendingDeliveries + lowStock + criticalStock + pendingVerifications;
}

final warehouseAlertsProvider =
    FutureProvider.autoDispose<WarehouseAlerts>((ref) async {
  final dash = ref.watch(homeOwnerPeriodDashboardProvider);
  final alerts = await ref.watch(stockAlertCountsProvider.future);
  final variances = ref.watch(stockVariancesTodayProvider).valueOrNull ?? [];
  return WarehouseAlerts(
    pendingDeliveries: dash.pendingDeliveryCount,
    lowStock: alerts.low,
    criticalStock: alerts.critical,
    pendingVerifications: variances.length,
  );
});
