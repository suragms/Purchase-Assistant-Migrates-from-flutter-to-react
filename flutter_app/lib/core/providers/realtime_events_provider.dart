import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../platform/app_foreground_provider.dart';
import 'business_aggregates_invalidation.dart';
import 'low_stock_providers.dart';
import 'stock_providers.dart';
import 'trade_purchases_provider.dart';

void invalidateAfterStockWrite(WidgetRef ref, {String? itemId}) {
  invalidateWarehouseSurfacesLight(ref, itemId: itemId);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(lowStockOperationsSummaryProvider);
}

void invalidateAfterPurchaseWrite(WidgetRef ref) {
  ref.invalidate(tradePurchasesListProvider);
  invalidateAfterStockWrite(ref);
}

@visibleForTesting
Set<String> itemIdsFromRealtimePayload(Map<String, dynamic>? payload) {
  if (payload == null || payload.isEmpty) return const {};
  final out = <String>{};
  final single = payload['item_id']?.toString();
  if (single != null && single.isNotEmpty) out.add(single);
  final many = payload['item_ids'];
  if (many is List) {
    for (final raw in many) {
      final id = raw?.toString() ?? '';
      if (id.isNotEmpty) out.add(id);
    }
  }
  return out;
}

/// What changed on the latest realtime poll (consumers decide how to refresh).
class RealtimeInvalidationSignal {
  const RealtimeInvalidationSignal({
    required this.tick,
    this.notifications = false,
    this.warehouse = false,
    this.delivery = false,
    this.affectedItemIds = const {},
  });

  final int tick;
  final bool notifications;
  final bool warehouse;
  final bool delivery;
  final Set<String> affectedItemIds;
}

/// Polls server events; does **not** invalidate providers itself (avoids double-refresh).
final realtimeInvalidationProvider =
    StreamProvider<RealtimeInvalidationSignal>((ref) async* {
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());

  if (providerSkipApi(ref)) return;
  final session = ref.watch(sessionProvider);
  if (session == null) return;
  final role = session.primaryBusiness.role.toLowerCase();
  if (role == 'staff') return;
  final api = ref.read(hexaApiProvider);
  final seen = <String>{};
  var tick = 0;

  Future<RealtimeInvalidationSignal> poll({required bool initial}) async {
    if (providerSkipApi(ref)) {
      return RealtimeInvalidationSignal(tick: tick);
    }
    List<Map<String, dynamic>> rows;
    try {
      rows = await api.listRealtimeEvents(
        businessId: session.primaryBusiness.id,
        limit: 40,
      );
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 401) {
        ref.read(authApiGateProvider.notifier).suspendFor401();
      }
      return RealtimeInvalidationSignal(tick: tick);
    }
    var notifications = false;
    var warehouse = false;
    var delivery = false;
    final affectedItemIds = <String>{};
    for (final row in rows) {
      final key =
          '${row['type']}:${row['created_at']}:${row['payload']?.toString() ?? ''}';
      if (!seen.add(key) || initial) continue;
      final type = row['type']?.toString() ?? '';
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'] as Map)
          : null;
      if (type == 'notification.changed') {
        notifications = true;
      } else if (type == 'stock.changed' ||
          type == 'stock.activity_changed' ||
          type == 'purchase.changed') {
        warehouse = true;
        if (type == 'purchase.changed') delivery = true;
        affectedItemIds.addAll(itemIdsFromRealtimePayload(payload));
      }
    }
    return RealtimeInvalidationSignal(
      tick: tick,
      notifications: notifications,
      warehouse: warehouse,
      delivery: delivery,
      affectedItemIds: affectedItemIds,
    );
  }

  yield await poll(initial: true);
  final timer = Stream.periodic(const Duration(seconds: 15));
  await for (final _ in timer) {
    if (ref.read(sessionProvider) == null ||
        ref.read(authSessionExpiredProvider) ||
        !ref.read(appForegroundProvider)) {
      continue;
    }
    tick++;
    yield await poll(initial: false);
  }
});
