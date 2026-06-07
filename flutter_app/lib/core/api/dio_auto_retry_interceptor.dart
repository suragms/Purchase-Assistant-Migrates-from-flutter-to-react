import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../auth/auth_error_messages.dart' show dioIsAutoRetryableTransport;

/// Retries safe, idempotent requests up to [maxAttempts] on transient failures.
/// Register on the main [Dio] after other interceptors; [onError] order is last-registered first.
class DioAutoRetryInterceptor extends Interceptor {
  DioAutoRetryInterceptor(this._dio, {this.maxAttempts = 3});

  final Dio _dio;
  /// Counts automatic refetches after the first failure (bounded by [maxAttempts]).
  final int maxAttempts;

  bool _retryable(DioException err) {
    if (err.requestOptions.extra['skipAutoRetry'] == true) return false;
    final m = err.requestOptions.method.toUpperCase();
    if (m != 'GET' && m != 'HEAD') return false;
    if (dioIsAutoRetryableTransport(err)) return true;
    final sc = err.response?.statusCode;
    // 503: short backoff only (local DB cold start / transient outage).
    return sc == 502 || sc == 503 || sc == 504;
  }

  int _delayMs(DioException err, int attempt) {
    final sc = err.response?.statusCode;
    if (sc == 503) {
      return const [3000, 6000, 12000, 20000][math.min(attempt - 1, 3)];
    }
    return const [100, 300, 900][math.min(attempt - 1, 2)];
  }

  int _maxAttemptsFor(DioException err) {
    if (err.response?.statusCode == 503) return 4;
    return maxAttempts;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_retryable(err)) {
      return handler.next(err);
    }
    var current = err;
    var n = (current.requestOptions.extra['dio_auto_retry'] as int?) ?? 0;
    final cap = _maxAttemptsFor(current);
    while (n < cap) {
      n += 1;
      current.requestOptions.extra['dio_auto_retry'] = n;
      await Future<void>.delayed(Duration(milliseconds: _delayMs(current, n)));
      try {
        final res = await _dio.fetch(current.requestOptions);
        return handler.resolve(res);
      } on DioException catch (e) {
        if (!_retryable(e)) {
          return handler.next(e);
        }
        current = e;
        if (n >= _maxAttemptsFor(e)) {
          return handler.next(e);
        }
      }
    }
    return handler.next(current);
  }
}
