import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import '../services/stock_offline_sync.dart';
import 'business_aggregates_invalidation.dart';

final stockOfflinePendingCountProvider = Provider<int>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return 0;
  return OfflineStore.pendingStockQueueCount(session.primaryBusiness.id);
});

final stockOfflineSyncProvider =
    AsyncNotifierProvider<StockOfflineSyncNotifier, void>(StockOfflineSyncNotifier.new);

class StockOfflineSyncNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> syncNow() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await replayStockOfflineQueue(
        ref: ref,
        businessId: session.primaryBusiness.id,
      );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockOfflinePendingCountProvider);
    });
  }
}
