import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../notifications/local_notifications_service.dart';
import '../providers/business_aggregates_invalidation.dart';
import '../providers/prefs_provider.dart';
import 'offline_store.dart';

/// Background sync for queued offline writes (purchase saves).
///
/// Rules:
/// - Never blocks UI.
/// - Best-effort only; failures keep the entry queued.
/// - On success, invalidates cached aggregates so the UI silently refreshes.
class OfflineSyncService {
  OfflineSyncService._();

  static Timer? _poll;
  static bool _running = false;

  static void start(ProviderContainer container) {
    _poll ??= Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(runOnce(container)),
    );
    unawaited(runOnce(container));
  }

  static void stop() {
    _poll?.cancel();
    _poll = null;
  }

  static bool _isNetworkError(DioException e) {
    final t = e.type;
    return t == DioExceptionType.connectionError ||
        t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout;
  }

  static Future<void> runOnce(ProviderContainer container) async {
    if (_running) return;
    _running = true;
    try {
      final session = container.read(sessionProvider);
      if (session == null) return;
      final api = container.read(hexaApiProvider);
      final bid = session.primaryBusiness.id;

      final pending = OfflineStore.getPendingEntries();
      if (pending.isEmpty) return;

      var syncedCount = 0;
      for (final e in pending) {
        final id = e['id']?.toString() ?? '';
        final data = e['data'];
        if (id.isEmpty || data is! Map) continue;
        final kind = data['kind']?.toString() ?? '';
        final businessId = data['businessId']?.toString() ?? '';
        if (kind != 'trade_purchase_create') continue;
        if (businessId.isEmpty || businessId != bid) continue;
        final body = data['body'];
        if (body is! Map) continue;

        try {
          await api.createTradePurchase(
            businessId: bid,
            body: Map<String, dynamic>.from(body),
          );
          await OfflineStore.markSynced(id);
          syncedCount++;
          invalidatePurchaseWorkspace(container);
        } on DioException catch (ex) {
          // If server says duplicate, drop it (it likely synced elsewhere).
          if (ex.response?.statusCode == 409) {
            await OfflineStore.markSynced(id);
            syncedCount++;
            continue;
          }
          if (_isNetworkError(ex)) {
            // Still offline; stop early.
            return;
          }
          // Other errors: keep queued (user can re-open and fix later).
          if (kDebugMode) {
            debugPrint('[OfflineSync] failed kind=$kind id=$id status=${ex.response?.statusCode}');
          }
        } catch (_) {
          // Keep queued.
        }
      }
      if (syncedCount > 0 &&
          container.read(localNotificationsOptInProvider)) {
        unawaited(LocalNotificationsService.instance
            .showOfflineSyncSuccess(count: syncedCount));
      }
    } finally {
      _running = false;
    }
  }

  /// Deterministic fingerprint used for deduping queued entries.
  static String fingerprintForTradePurchaseCreate(Map<String, dynamic> body) {
    try {
      final canonical = jsonEncode(body);
      return canonical.hashCode.toString();
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
}

