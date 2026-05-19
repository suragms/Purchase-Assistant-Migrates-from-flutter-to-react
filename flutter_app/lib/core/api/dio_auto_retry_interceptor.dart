import 'dart:math' as math;

import 'package:dio/dio.dart';

/// Retries safe, idempotent requests up to [maxAttempts] on transient failures.
/// Register on the main [Dio] after other interceptors; [onError] order is last-registered first.
class DioAutoRetryInterceptor extends Interceptor {
  DioAutoRetryInterceptor(this._dio, {this.maxAttempts = 4});

  final Dio _dio;
  /// Counts automatic refetches after the first failure (bounded by [maxAttempts]).
  final int maxAttempts;

  bool _retryable(DioException err) {
    if (err.requestOptions.extra['skipAutoRetry'] == true) return false;
    final m = err.requestOptions.method.toUpperCase();
    if (m != 'GET' && m != 'HEAD') return false;
    final t = err.type;
    if (t == DioExceptionType.connectionError ||
        t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout) {
      return true;
    }
    final sc = err.response?.statusCode;
    // 503: short backoff only (local DB cold start / transient outage).
    return sc == 502 || sc == 503 || sc == 504 || sc == 500;
  }

  int _delayMs(DioException err, int attempt) {
    final sc = err.response?.statusCode;
    if (sc == 503) {
      return const [2000, 4000][math.min(attempt - 1, 1)];
    }
    return const [100, 300, 900][math.min(attempt - 1, 2)];
  }

  int _maxAttemptsFor(DioException err) {
    if (err.response?.statusCode == 503) return 2;
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
