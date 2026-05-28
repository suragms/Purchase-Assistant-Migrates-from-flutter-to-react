import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'business_aggregates_invalidation.dart';
import 'business_write_revision.dart';
import 'home_owner_dashboard_providers.dart';
import 'low_stock_providers.dart';
import 'stock_providers.dart';
import 'trade_purchases_provider.dart';

void invalidateAfterStockWrite(WidgetRef ref) {
  ref.invalidate(stockListProvider);
  ref.invalidate(stockStatusCountsProvider);
  ref.invalidate(homeInventorySummaryProvider);
  ref.invalidate(lowStockOperationsSummaryProvider);
  ref.read(businessDataWriteRevisionProvider.notifier).state++;
}

void invalidateAfterPurchaseWrite(WidgetRef ref) {
  ref.invalidate(tradePurchasesListProvider);
  invalidateAfterStockWrite(ref);
}

final realtimeInvalidationProvider = StreamProvider.autoDispose<int>((ref) async* {
  final session = ref.watch(sessionProvider);
  if (session == null) return;
  final api = ref.read(hexaApiProvider);
  final seen = <String>{};
  var tick = 0;

  Future<void> poll({required bool initial}) async {
    final rows = await api.listRealtimeEvents(
      businessId: session.primaryBusiness.id,
      limit: 40,
    );
    var shouldInvalidateNotifications = false;
    var shouldInvalidateWarehouse = false;
    for (final row in rows) {
      final key =
          '${row['type']}:${row['created_at']}:${row['payload']?.toString() ?? ''}';
      if (!seen.add(key) || initial) continue;
      final type = row['type']?.toString() ?? '';
      if (type == 'notification.changed') {
        shouldInvalidateNotifications = true;
      } else if (type == 'stock.changed' ||
          type == 'stock.activity_changed' ||
          type == 'purchase.changed') {
        shouldInvalidateWarehouse = true;
      }
    }
    if (shouldInvalidateNotifications) {
      invalidateNotificationSurfaces(ref);
    }
    if (shouldInvalidateWarehouse) {
      invalidateWarehouseSurfaces(ref);
    }
  }

  await poll(initial: true);
  yield tick;
  final timer = Stream.periodic(const Duration(seconds: 30));
  await for (final _ in timer) {
    await poll(initial: false);
    yield ++tick;
  }
});
