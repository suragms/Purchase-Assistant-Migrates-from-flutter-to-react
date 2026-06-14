import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../api/api_warmup.dart';
import '../auth/session_notifier.dart' show hexaApiProvider, sessionProvider;
import '../providers/business_aggregates_invalidation.dart';
import '../providers/business_write_revision.dart'
    show markWarehouseGlobalInvalidated, warehouseGlobalInvalidateRecently;
import '../providers/stock_providers.dart' show stockListLastFetchedAtProvider;
import '../navigation/surface_refresh_policy.dart' show kStockListCacheTtl;
import '../providers/realtime_events_provider.dart';
import '../services/backup_auto_service.dart';
import 'app_foreground_provider.dart';
import 'app_visibility_stub.dart'
    if (dart.library.html) 'app_visibility_web.dart' as app_visibility;

/// Pauses API while backgrounded; refreshes tokens once when returning (web + mobile).
class AppForegroundListener extends ConsumerStatefulWidget {
  const AppForegroundListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppForegroundListener> createState() =>
      _AppForegroundListenerState();
}

class _AppForegroundListenerState extends ConsumerState<AppForegroundListener>
    with WidgetsBindingObserver {
  Timer? _resumeDebounce;
  bool _foreground = true;
  DateTime? _lastForegroundRefreshAt;
  DateTime? _lastWarehouseInvalidateAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app_visibility.bindWebTabVisibility(_onWebVisibility);
  }

  @override
  void dispose() {
    _resumeDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    app_visibility.unbindWebTabVisibility();
    super.dispose();
  }

  void _onWebVisibility(bool visible) {
    _setForeground(visible, source: 'web');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    _setForeground(fg, source: 'lifecycle');
  }

  void _setForeground(bool fg, {required String source}) {
    if (_foreground == fg) return;
    _foreground = fg;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!fg) {
        _resumeDebounce?.cancel();
        ref.read(authResumeGateProvider.notifier).state = false;
        ref.read(appForegroundProvider.notifier).state = false;
        return;
      }
      // Web IndexedStack keeps tabs mounted — resume gate caused auth_blocked on all pages.
      if (!kIsWeb) {
        ref.read(authResumeGateProvider.notifier).state = true;
      }
      ref.read(appForegroundProvider.notifier).state = true;
      ref.read(appLastForegroundAtProvider.notifier).state = DateTime.now();
      _resumeDebounce?.cancel();
      _resumeDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        unawaited(_onReturnedToForeground());
      });
    });
  }

  Future<void> _onReturnedToForeground() async {
    try {
      final session = ref.read(sessionProvider);
      if (session == null) {
        ref.read(authResumeGateProvider.notifier).state = false;
        return;
      }
      try {
        await ref.read(sessionProvider.notifier).silentRefreshIfNeeded();
      } catch (_) {
        // Keep session; Dio interceptor will refresh on next call.
      }
      if (!mounted) return;
      try {
        ref.read(authApiGateProvider.notifier).clearSuspend();
      } catch (_) {}
      // Warm API before invalidation storm (Render cold-start mitigation).
      try {
        await ApiWarmupService.pingHealth(ref.read(hexaApiProvider));
      } catch (_) {}
      if (!mounted) return;
      final now = DateTime.now();
      if (_lastForegroundRefreshAt != null &&
          now.difference(_lastForegroundRefreshAt!) <
              const Duration(seconds: 2)) {
        return;
      }
      _lastForegroundRefreshAt = now;
      // Always refresh staff/warehouse summaries on resume (light invalidation).
      invalidateStaffDeliverySurfacesLight(ref);
      if (warehouseGlobalInvalidateRecently(ref)) {
        ref.invalidate(realtimeInvalidationProvider);
        return;
      }
      if (_lastWarehouseInvalidateAt != null &&
          now.difference(_lastWarehouseInvalidateAt!) <
              const Duration(seconds: 30)) {
        ref.invalidate(realtimeInvalidationProvider);
        return;
      }
      _lastWarehouseInvalidateAt = now;
      markWarehouseGlobalInvalidated(ref);
      final stockFetched = ref.read(stockListLastFetchedAtProvider);
      final stockCacheFresh = stockFetched != null &&
          now.difference(stockFetched) < kStockListCacheTtl;
      if (!stockCacheFresh) {
        invalidateWarehouseSurfacesLight(ref);
      }
      ref.invalidate(realtimeInvalidationProvider);
      unawaited(maybeRunDailyAutoBackup(ref));
    } finally {
      if (mounted) {
        ref.read(authResumeGateProvider.notifier).state = false;
        ref.read(authRefreshInFlightProvider.notifier).state = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
