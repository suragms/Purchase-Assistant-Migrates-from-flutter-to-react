import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/provider_api_guard.dart';
import '../../core/providers/business_aggregates_invalidation.dart';
import '../../core/providers/business_write_revision.dart';
import '../../core/providers/home_owner_dashboard_providers.dart'
    show homeInventorySummaryProvider, homeRecentActivityFeedProvider;
import '../../core/providers/realtime_events_provider.dart';

/// Single shell-level realtime fan-out (not tied to Home tab mount).
class ShellRealtimeListener extends ConsumerStatefulWidget {
  const ShellRealtimeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShellRealtimeListener> createState() =>
      _ShellRealtimeListenerState();
}

class _ShellRealtimeListenerState extends ConsumerState<ShellRealtimeListener> {
  int _lastTick = 0;
  DateTime? _lastWarehouseInvalidate;
  Timer? _warehouseDebounce;
  RealtimeInvalidationSignal? _pendingWarehouseSignal;

  bool _throttleWarehouse() {
    final now = DateTime.now();
    if (_lastWarehouseInvalidate != null &&
        now.difference(_lastWarehouseInvalidate!).inSeconds < 8) {
      return true;
    }
    _lastWarehouseInvalidate = now;
    return false;
  }

  @override
  void dispose() {
    _warehouseDebounce?.cancel();
    super.dispose();
  }

  void _scheduleWarehouseInvalidate(RealtimeInvalidationSignal signal) {
    _pendingWarehouseSignal = signal;
    _warehouseDebounce?.cancel();
    _warehouseDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || providerSkipApi(ref)) return;
      final pending = _pendingWarehouseSignal;
      _pendingWarehouseSignal = null;
      if (pending == null || !pending.warehouse) return;
      _applyWarehouseSignal(pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeInvalidationProvider, (prev, next) {
      final signal = next.valueOrNull;
      if (signal == null || signal.tick == _lastTick) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || providerSkipApi(ref)) return;
        if (signal.tick == _lastTick) return;
        _lastTick = signal.tick;
        _applyRealtimeSignal(signal);
      });
    });
    return widget.child;
  }

  void _applyRealtimeSignal(RealtimeInvalidationSignal signal) {
      if (signal.notifications) {
        invalidateNotificationSurfaces(ref);
      }
      if (signal.delivery) {
        invalidateStaffDeliverySurfacesLight(ref);
      }
      if (signal.warehouse) {
        final urgent = signal.affectedItemIds.isNotEmpty;
        if (urgent || !_throttleWarehouse()) {
          _scheduleWarehouseInvalidate(signal);
        }
      }
      if (signal.notifications || signal.delivery || signal.warehouse) {
        bumpRemoteBusinessDataRevision(ref);
      }
  }

  void _applyWarehouseSignal(RealtimeInvalidationSignal signal) {
    final ids = signal.affectedItemIds.where((id) => id.isNotEmpty).toSet();
    if (ids.length == 1) {
      patchStockItemInCache(ref, ids.first, const {});
    } else if (ids.isEmpty) {
      invalidateWarehouseSurfacesLight(ref);
    } else {
      invalidateWarehouseSurfacesLight(ref);
      for (final id in ids) {
        invalidateWarehouseItemSurfacesLight(ref, itemId: id);
      }
    }
    ref.invalidate(homeRecentActivityFeedProvider);
    ref.invalidate(homeInventorySummaryProvider);
  }
}
