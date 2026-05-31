import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../../features/shell/shell_branch_provider.dart';
import 'business_aggregates_invalidation.dart' show invalidateNotificationSurfaces;
import 'server_notifications_provider.dart';
import 'notifications_provider.dart' show NotificationItem, mergedNotificationFeedProvider;
import 'warehouse_alerts_provider.dart';

/// Primes notification + warehouse providers. Periodic refresh owned by Home (60s).
final notificationCenterCoordinatorProvider =
    Provider.autoDispose<void>((ref) {
  if (providerSkipApi(ref)) return;

  ref.watch(appNotificationsListProvider);
  ref.watch(warehouseAlertsProvider);

  final onHome = ref.watch(shellCurrentBranchProvider) == ShellBranch.home;
  if (onHome) return;

  final timer = Timer.periodic(const Duration(seconds: 120), (_) {
    invalidateNotificationSurfaces(ref);
    ref.invalidate(warehouseAlertsProvider);
  });
  ref.onDispose(timer.cancel);
});

final homeWarehouseAlertsProvider =
    Provider.autoDispose<AsyncValue<WarehouseAlerts>>((ref) {
  ref.watch(notificationCenterCoordinatorProvider);
  return ref.watch(warehouseAlertsProvider);
});

final notificationFeedForUiProvider =
    Provider.autoDispose<List<NotificationItem>>((ref) {
  ref.watch(notificationCenterCoordinatorProvider);
  return ref.watch(mergedNotificationFeedProvider);
});
