import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

import 'hexa_api.dart';

/// Cold PaaS warm-up (`/health/ready` + `/health`) and optional periodic ping.
class ApiWarmupService {
  ApiWarmupService._();

  static Timer? _keepAlive;

  /// Call before authenticated traffic: probes `/health/ready` (DB) then `/health`.
  /// Retries help sleepy PaaS cold starts; **stops immediately** on connection refused
  /// (nothing listening) so local dev does not hammer `/health` hundreds of times.
  static Future<void> pingHealth(
    HexaApi api, {
    VoidCallback? onSlow,
    VoidCallback? onUnreachable,
  }) async {
    final slow = Timer(const Duration(seconds: 3), () => onSlow?.call());
    const attempts = 5;
    const timeout = Duration(seconds: 10);
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await api.healthReady().timeout(timeout);
        slow.cancel();
        return;
      } catch (e) {
        if (_isUnreachableHost(e)) {
          slow.cancel();
          onUnreachable?.call();
          return;
        }
        try {
          await api.health().timeout(timeout);
          slow.cancel();
          return;
        } catch (e2) {
          if (_isUnreachableHost(e2)) {
            slow.cancel();
            onUnreachable?.call();
            return;
          }
          if (attempt < attempts - 1) {
            await Future<void>.delayed(Duration(seconds: attempt + 1));
          }
        }
      }
    }
    slow.cancel();
  }

  static bool _isUnreachableHost(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError;
    }
    return false;
  }

  /// Keeps sleepy hosts warmer during a session (battery/network tradeoff).
  static void startPeriodicHealth(HexaApi api) {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(() async {
        try {
          await api.healthReady().timeout(const Duration(seconds: 12));
        } catch (_) {
          try {
            await api.health().timeout(const Duration(seconds: 12));
          } catch (_) {}
        }
      }());
    });
  }

  static void stopPeriodicHealth() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }
}
