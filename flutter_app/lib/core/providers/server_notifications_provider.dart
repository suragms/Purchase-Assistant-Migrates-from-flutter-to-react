import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Server-backed in-app notifications (GET …/notifications).
final appNotificationsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), keepAlive.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listAppNotifications(
        businessId: session.primaryBusiness.id,
      );
});

final appNotificationUnreadCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return 0;
  return ref.read(hexaApiProvider).appNotificationUnreadCount(
        businessId: session.primaryBusiness.id,
      );
});

final appNotificationsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const {};
  return ref.read(hexaApiProvider).appNotificationsSummary(
        businessId: session.primaryBusiness.id,
      );
});
