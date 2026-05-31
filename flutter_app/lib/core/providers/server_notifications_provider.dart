import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;

/// Server-backed in-app notifications (GET …/notifications).
final appNotificationsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 120), keepAlive.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listAppNotifications(
        businessId: session.primaryBusiness.id,
      );
});

final appNotificationUnreadCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  if (providerSkipApi(ref)) return 0;
  final session = ref.watch(activeSessionProvider)!;
  return ref.read(hexaApiProvider).appNotificationUnreadCount(
        businessId: session.primaryBusiness.id,
      );
});

final appNotificationsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (providerSkipApi(ref)) return const {};
  final session = ref.watch(activeSessionProvider)!;
  return ref.read(hexaApiProvider).appNotificationsSummary(
        businessId: session.primaryBusiness.id,
      );
});
