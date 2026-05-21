import 'dart:math' show min;

import 'dart:math' show Random;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http_parser/http_parser.dart';

import 'dio_auto_retry_interceptor.dart';
import '../config/app_config.dart';
import '../models/session.dart';
import '../strict_decimal.dart';

/// Transient failures only — do not retry after a full response (avoids duplicate assistant turns).
bool _retryableAssistantRequest(DioException e) {
  final sc = e.response?.statusCode;
  if (sc != null && (sc == 502 || sc == 503 || sc == 504)) return true;
  final t = e.type;
  return t == DioExceptionType.connectionError ||
      t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout;
}

bool _reports404HintLogged = false;

/// Correlates app failures with Render/API logs (echoed as `X-Request-Id`).
String _newRequestCorrelationId() {
  const hex = '0123456789abcdef';
  final r = Random();
  String seg(int n) =>
      List.generate(n, (_) => hex[r.nextInt(16)]).join();
  return '${seg(8)}-${seg(4)}-${seg(4)}-${seg(4)}-${seg(12)}';
}

/// Trade report endpoints normally return a JSON array; tolerate wrapped maps.
List<Map<String, dynamic>> _parseJsonMapList(dynamic data) {
  if (data is List) {
    return data
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }
  if (data is Map) {
    for (final key in const ['items', 'data', 'rows', 'results']) {
      final inner = data[key];
      final out = _parseJsonMapList(inner);
      if (out.isNotEmpty) return out;
    }
  }
  return [];
}

/// Bill scans upload multi‑MB images and may wait on OCR/LLM — avoid false timeouts.
Options get _scanMultipartOptions => Options(
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 120),
    );

Options get _scanPollOptions => Options(
      receiveTimeout: const Duration(seconds: 45),
    );

bool _isAuthEndpoint(String path) {
  return path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/google') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/forgot-password') ||
      path.contains('/auth/reset-password');
}

class _BusinessConnectivityBannerInterceptor extends Interceptor {
  _BusinessConnectivityBannerInterceptor(this._fn);

  final void Function(bool degraded, String? hint)? _fn;

  static bool _biz(String p) =>
      p.startsWith('/v1/') && !_isAuthEndpoint(p);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final fn = _fn;
    final path = response.requestOptions.uri.path;
    if (fn != null &&
        _biz(path) &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      final dbDown =
          response.headers.value('x-database-unavailable') == '1';
      if (dbDown) {
        fn(true, 'Database temporarily unavailable');
      } else {
        fn(false, null);
      }
    }
    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final fn = _fn;
    final path = err.requestOptions.uri.path;
    if (fn != null && _biz(path) && !_isAuthEndpoint(path)) {
      final sc = err.response?.statusCode;
      if (sc == 503) {
        final h = err.response?.headers.value('x-database-unavailable');
        fn(true, h == '1' ? 'Database temporarily unavailable' : null);
      } else if (err.type == DioExceptionType.connectionError ||
          err.type == DioExceptionType.receiveTimeout ||
          err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.sendTimeout ||
          (sc != null && sc >= 502 && sc <= 504)) {
        fn(true, null);
      }
    }
    return handler.next(err);
  }
}

class HexaApi {
  HexaApi({
    String? baseUrl,
    Future<bool> Function()? onUnauthorizedRefresh,
    Future<String?> Function()? resolveAccessToken,
    void Function(bool degraded, String? hint)? onConnectivityBanner,
  })  : _onUnauthorizedRefresh = onUnauthorizedRefresh,
        _resolveAccessToken = resolveAccessToken,
        _onConnectivityBanner = onConnectivityBanner,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ),
        _plain = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final h = options.headers;
          final raw = h['x-request-id'] ?? h['X-Request-Id'];
          final s = raw?.toString().trim() ?? '';
          if (s.isEmpty) {
            h['x-request-id'] = _newRequestCorrelationId();
          }
          return handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        // Belt-and-suspenders: if a request goes out without an Authorization
        // header (e.g. cold start fires before SessionNotifier.restore has
        // called setAuthToken), resolve the token from the secure store and
        // attach it. Skips auth endpoints. Prevents the "empty dashboard,
        // random 401s on first paint" class of bugs.
        onRequest: (options, handler) async {
          final path = options.uri.path;
          if (_isAuthEndpoint(path)) {
            return handler.next(options);
          }
          final existing = options.headers['Authorization']?.toString() ??
              _dio.options.headers['Authorization']?.toString();
          if (existing == null || existing.isEmpty) {
            final resolver = _resolveAccessToken;
            if (resolver != null) {
              try {
                final token = await resolver();
                if (token != null && token.isNotEmpty) {
                  final h = 'Bearer $token';
                  _dio.options.headers['Authorization'] = h;
                  options.headers['Authorization'] = h;
                }
              } catch (_) {
                // Resolver failed; let the request go and 401 interceptor handle it.
              }
            }
          }
          return handler.next(options);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          if (err.response?.statusCode != 401) {
            return handler.next(err);
          }
          final req = err.requestOptions;
          if (req.extra['authRetried'] == true) {
            return handler.next(err);
          }
          if (_isAuthEndpoint(req.uri.path)) {
            return handler.next(err);
          }
          final ok = await _onUnauthorizedRefresh?.call() ?? false;
          if (!ok) {
            return handler.next(err);
          }
          final auth = _dio.options.headers['Authorization'];
          if (auth != null) {
            req.headers['Authorization'] = auth;
          }
          req.extra['authRetried'] = true;
          try {
            final res = await _dio.fetch(req);
            return handler.resolve(res);
          } on DioException catch (e) {
            return handler.next(e);
          }
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException err, ErrorInterceptorHandler handler) {
          if (kDebugMode) {
            final req = err.requestOptions;
            final sent = req.headers['x-request-id']?.toString();
            final echoed = err.response?.headers.value('x-request-id') ??
                err.response?.headers.value('X-Request-Id');
            if ((sent != null && sent.isNotEmpty) ||
                (echoed != null && echoed.isNotEmpty)) {
              debugPrint(
                'HexaApi: ${req.uri.path} x-request-id=${echoed ?? sent} '
                '(search this id in API / Render logs)',
              );
            }
          }
          if (err.response?.statusCode == 404) {
            final p = err.requestOptions.uri.path;
            if (p.contains('/reports/') && !_reports404HintLogged) {
              _reports404HintLogged = true;
              debugPrint(
                'HexaApi: 404 on a reports request ($p). If your backend includes '
                'the reports routes (e.g. reports/trade-suppliers), restart the API from '
                'the current `main` and point the app at the same base URL and port as '
                'the running server.',
              );
            }
          }
          return handler.next(err);
        },
      ),
    );
    _dio.interceptors.add(DioAutoRetryInterceptor(_dio, maxAttempts: 4));
    final banner = _onConnectivityBanner;
    if (banner != null) {
      _dio.interceptors.add(_BusinessConnectivityBannerInterceptor(banner));
    }
  }

  final Dio _dio;
  final Dio _plain;
  final Future<bool> Function()? _onUnauthorizedRefresh;
  final Future<String?> Function()? _resolveAccessToken;
  final void Function(bool degraded, String? hint)? _onConnectivityBanner;

  Dio get raw => _dio;

  /// Public health check (no auth). Used for AI status indicator.
  Future<Map<String, dynamic>> health() async {
    final res = await _plain.get<Map<String, dynamic>>('/health');
    return res.data ?? <String, dynamic>{};
  }

  /// DB readiness probe (503 when DB unreachable).
  Future<Map<String, dynamic>> healthReady() async {
    final res = await _plain.get<Map<String, dynamic>>('/health/ready');
    return res.data ?? <String, dynamic>{};
  }

  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  ({String access, String refresh}) _tokenPairFromResponse(
      Response<Map<String, dynamic>> res) {
    final d = res.data!;
    return (
      access: d['access_token'] as String,
      refresh: d['refresh_token'] as String
    );
  }

  Future<({String access, String refresh})> login({
    required String identifier,
    required String password,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {'identifier': identifier.trim(), 'password': password},
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> register({
    required String username,
    required String email,
    required String password,
    String? name,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> loginWithGoogle(
      {required String idToken}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/google',
      data: {'id_token': idToken},
    );
    return _tokenPairFromResponse(res);
  }

  /// Request a password reset (no auth). In development the response may include `dev_reset_token`.
  Future<Map<String, dynamic>> requestPasswordReset({required String email}) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/forgot-password',
      data: {'email': email.trim().toLowerCase()},
    );
    return res.data ?? <String, dynamic>{};
  }

  /// Apply new password using the token from the reset link (no auth).
  Future<Map<String, dynamic>> resetPasswordWithToken({
    required String token,
    required String newPassword,
  }) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/reset-password',
      data: {
        'token': token,
        'new_password': newPassword,
      },
    );
    return res.data ?? <String, dynamic>{};
  }

  /// No Bearer header — uses body only. Kept on [_plain] so it never inherits [setAuthToken].
  Future<({String access, String refresh})> refreshTokens(
      {required String refreshToken}) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return _tokenPairFromResponse(res);
  }

  Future<List<BusinessBrief>> meBusinesses() async {
    final res = await _dio.get<dynamic>('/v1/me/businesses');
    final data = res.data;
    if (data is! List) return [];
    return data
        .map((e) => BusinessBrief.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> meProfile() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/me/profile');
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<List<Map<String, dynamic>>> listAppNotifications({
    required String businessId,
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/notifications',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<int> appNotificationUnreadCount({required String businessId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/notifications/unread-count',
    );
    final u = res.data?['unread'];
    if (u is int) return u;
    if (u is num) return u.round();
    return 0;
  }

  Future<Map<String, dynamic>> patchAppNotificationRead({
    required String businessId,
    required String notificationId,
    bool read = true,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/notifications/$notificationId',
      data: {'read': read},
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<List<Map<String, dynamic>>> listActivityLog({
    required String businessId,
    String period = 'today',
    int page = 1,
    int perPage = 50,
    String? userId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/activity-log',
      queryParameters: {
        'period': period,
        'page': page,
        'per_page': perPage,
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> postActivityLog({
    required String businessId,
    required String actionType,
    String? itemId,
    String? itemName,
    Map<String, dynamic>? details,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/activity-log',
      data: {
        'action_type': actionType,
        if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
        if (itemName != null && itemName.isNotEmpty) 'item_name': itemName,
        if (details != null && details.isNotEmpty) 'details': details,
      },
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<List<Map<String, dynamic>>> listBusinessUsers(
      {required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/users');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Creates staff/manager login. Response may include `generated_password`.
  Future<Map<String, dynamic>> createBusinessUser({
    required String businessId,
    required String fullName,
    required String phone,
    required String role,
    String? password,
    String? username,
    String? notes,
    bool isActive = true,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users',
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'role': role,
        'is_active': isActive,
        if (password != null && password.trim().isNotEmpty) 'password': password.trim(),
        if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> patchBusinessUser({
    required String businessId,
    required String userId,
    String? fullName,
    String? phone,
    String? role,
    bool? isActive,
    String? notes,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users/$userId',
      data: {
        if (fullName != null) 'full_name': fullName.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (role != null) 'role': role,
        if (isActive != null) 'is_active': isActive,
        if (notes != null) 'notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<List<Map<String, dynamic>>> listUserActivity({
    required String businessId,
    required String userId,
    int days = 30,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/activity-log',
      queryParameters: {'user_id': userId, 'days': days, 'per_page': 100},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listUserStockAdjustments({
    required String businessId,
    required String userId,
    int limit = 50,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/users/$userId/stock-adjustments',
      queryParameters: {'limit': limit},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listUserPurchases({
    required String businessId,
    required String userId,
    int limit = 50,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/users/$userId/purchases',
      queryParameters: {'limit': limit},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listUserLedger({
    required String businessId,
    required String userId,
    int limit = 80,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/users/$userId/ledger',
      queryParameters: {'limit': limit},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getUserPermissions({
    required String businessId,
    required String userId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users/$userId/permissions',
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<Map<String, dynamic>> patchUserPermissions({
    required String businessId,
    required String userId,
    required Map<String, bool> permissions,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users/$userId/permissions',
      data: {'permissions': permissions},
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<Map<String, dynamic>> getBusinessUser({
    required String businessId,
    required String userId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users/$userId',
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<Map<String, dynamic>> resetBusinessUserPassword({
    required String businessId,
    required String userId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/users/$userId/reset-password',
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<Map<String, dynamic>> superAdminHealth() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/admin/health');
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<Map<String, dynamic>> superAdminBusinessesOverview({int limit = 100}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/admin/businesses-overview',
      queryParameters: {'limit': limit},
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  /// Idempotent: ensure default workspace + catalog/supplier seed (single-tenant).
  /// Returns body JSON: `business_id`, `created_business`, `seeded`, optional `seed_stats`.
  /// Returns null when the server has no route (older API: 404/501) so session boot can continue.
  Future<Map<String, dynamic>?> bootstrapWorkspace() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/v1/me/bootstrap-workspace');
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d as Map);
      return null;
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 404 || sc == 501) {
        debugPrint(
            'hexa: bootstrap-workspace not available (HTTP $sc) — continuing without server seed');
        return null;
      }
      rethrow;
    }
  }

  /// Owner: optional in-app title + logo URL (HTTPS recommended).
  Future<Map<String, dynamic>> patchBusinessBranding({
    required String businessId,
    String? name,
    String? brandingTitle,
    String? brandingLogoUrl,
    String? gstNumber,
    String? address,
    String? phone,
    /// When true, always sends [contactEmail] (use empty string to clear).
    bool includeContactEmail = false,
    String? contactEmail,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding',
      data: {
        if (name != null) 'name': name,
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (includeContactEmail) 'contact_email': (contactEmail ?? '').trim(),
      },
    );
    return res.data ?? {};
  }

  /// Owner: multipart logo upload (JPEG/PNG/WebP).
  Future<Map<String, dynamic>> uploadBusinessLogo({
    required String businessId,
    required String filePath,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding/logo',
      data: formData,
    );
    return res.data ?? {};
  }

  /// Same as [uploadBusinessLogo] but from bytes (web-friendly).
  Future<Map<String, dynamic>> uploadBusinessLogoBytes({
    required String businessId,
    required List<int> bytes,
    String filename = 'logo.jpg',
  }) async {
    final lower = filename.toLowerCase();
    final MediaType ct;
    if (lower.endsWith('.png')) {
      ct = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      ct = MediaType('image', 'webp');
    } else {
      ct = MediaType('image', 'jpeg');
    }
    final formData = FormData.fromMap({
      'file':
          MultipartFile.fromBytes(bytes, filename: filename, contentType: ct),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding/logo',
      data: formData,
    );
    return res.data ?? {};
  }

  /// Bill image → structured preview (legacy wire shape; server uses same Vision pipeline as v2).
  Future<Map<String, dynamic>> scanPurchaseBillMultipart({
    required String businessId,
    required List<int> imageBytes,
    String filename = 'bill.jpg',
  }) async {
    final lower = filename.toLowerCase();
    final MediaType ct;
    if (lower.endsWith('.png')) {
      ct = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      ct = MediaType('image', 'webp');
    } else {
      ct = MediaType('image', 'jpeg');
    }
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes,
          filename: filename, contentType: ct),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/scan-purchase',
      queryParameters: {'business_id': businessId},
      data: formData,
      options: _scanMultipartOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Scanner v2: Bill image → OpenAI Vision → LLM parse → matching → validated preview table.
  Future<Map<String, dynamic>> scanPurchaseBillV2Multipart({
    required String businessId,
    required List<int> imageBytes,
    String filename = 'bill_scan.jpg',
  }) async {
    final lower = filename.toLowerCase();
    final MediaType ct;
    if (lower.endsWith('.png')) {
      ct = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      ct = MediaType('image', 'webp');
    } else {
      ct = MediaType('image', 'jpeg');
    }
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes,
          filename: filename, contentType: ct),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/scan-purchase-v2',
      queryParameters: {'business_id': businessId},
      data: formData,
      options: _scanMultipartOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Scanner v3: start async scan and return a scan_token immediately.
  Future<Map<String, dynamic>> scanPurchaseBillV3StartMultipart({
    required String businessId,
    required List<int> imageBytes,
    String filename = 'bill_scan.jpg',
  }) async {
    final lower = filename.toLowerCase();
    final MediaType ct;
    if (lower.endsWith('.png')) {
      ct = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      ct = MediaType('image', 'webp');
    } else {
      ct = MediaType('image', 'jpeg');
    }
    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes,
          filename: filename, contentType: ct),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/scan-purchase-v3/start',
      queryParameters: {'business_id': businessId},
      data: formData,
      options: _scanMultipartOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Scanner v3: poll current scan status/result.
  Future<Map<String, dynamic>> scanPurchaseBillV3Status({
    required String businessId,
    required String scanToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/me/scan-purchase-v3/status',
      queryParameters: {'business_id': businessId, 'scan_token': scanToken},
      options: _scanPollOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> scanPurchaseBillV2Correct({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/scan-purchase-v2/correct',
      queryParameters: {'business_id': businessId},
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> scanPurchaseBillV2Confirm({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<dynamic>(
      '/v1/me/scan-purchase-v2/confirm',
      queryParameters: {'business_id': businessId},
      data: body,
    );
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> scanPurchaseBillV2Update({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/scan-purchase-v2/update',
      queryParameters: {'business_id': businessId},
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> analyticsSummary(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/summary',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  /// Calendar-month composite dashboard (`month` = `YYYY-MM`). Full month window on server.
  Future<Map<String, dynamic>> getDashboard({
    required String businessId,
    required String month,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/dashboard',
      queryParameters: {'month': month},
    );
    return res.data ?? {};
  }

  /// Trade-purchase window insights (best/worst item by spend, supplier cost spread).
  Future<Map<String, dynamic>> analyticsInsights({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/insights/trade',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>?> getAnalyticsGoals({
    required String businessId,
    required String period,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/goals',
      queryParameters: {'period': period},
    );
    final d = res.data;
    if (d == null) return null;
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  Future<Map<String, dynamic>> putAnalyticsGoals({
    required String businessId,
    required String period,
    double? profitGoal,
    double? volumeGoal,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/goals',
      queryParameters: {'period': period},
      data: {
        if (profitGoal != null) 'profit_goal': profitGoal,
        if (volumeGoal != null) 'volume_goal': volumeGoal,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<dynamic>> listEntries({
    required String businessId,
    String? from,
    String? to,
    String? item,
    String? supplierId,
    String? brokerId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/entries',
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (item != null && item.isNotEmpty) 'item': item,
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
    );
    final items = res.data?['items'];
    if (items is List) return items;
    return [];
  }

  /// Unified catalog items + suppliers + entries (server-side substring match).
  Future<Map<String, dynamic>> unifiedSearch({
    required String businessId,
    required String q,
    /// Boosts catalog rows bought from this supplier (trade history + last_supplier_id).
    String? supplierId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/search',
      queryParameters: {
        'q': q,
        if (supplierId != null && supplierId.trim().isNotEmpty)
          'supplier_id': supplierId.trim(),
      },
    );
    return res.data ?? {};
  }

  /// GET `/trade-purchases` caps `limit` at 50; larger values are fetched in pages.
  static const int _kTradePurchasesApiMaxLimit = 50;

  Future<List<Map<String, dynamic>>> _listTradePurchasesPage({
    required String businessId,
    required int limit,
    required int offset,
    String? statusParam,
    String? q,
    String? supplierId,
    String? brokerId,
    String? catalogItemId,
    String? purchaseFrom,
    String? purchaseTo,
  }) async {
    final path = '/v1/businesses/$businessId/trade-purchases';
    final queryParameters = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      if (statusParam != null) 'status': statusParam,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (supplierId != null && supplierId.trim().isNotEmpty)
        'supplier_id': supplierId.trim(),
      if (brokerId != null && brokerId.trim().isNotEmpty)
        'broker_id': brokerId.trim(),
      if (catalogItemId != null && catalogItemId.trim().isNotEmpty)
        'catalog_item_id': catalogItemId.trim(),
      if (purchaseFrom != null && purchaseFrom.isNotEmpty)
        'purchase_from': purchaseFrom,
      if (purchaseTo != null && purchaseTo.isNotEmpty) 'purchase_to': purchaseTo,
    };

    if (kDebugMode) {
      debugPrint('HexaApi.listTradePurchases GET $path query=$queryParameters');
    }

    try {
      final res = await _dio.get<dynamic>(path, queryParameters: queryParameters);
      if (kDebugMode) {
        debugPrint('HexaApi.listTradePurchases status=${res.statusCode}');
      }
      final data = res.data;
      if (data is! List) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        if (kDebugMode) {
          debugPrint(
            'HexaApi.listTradePurchases 422 → [] (break poisoned-filter loops)',
          );
        }
        return [];
      }
      rethrow;
    }
  }

  /// Trade purchases (wholesale PUR-YYYY-XXXX flow).
  Future<List<Map<String, dynamic>>> listTradePurchases({
    required String businessId,
    int limit = 20,
    int offset = 0,
    String? status,
    String? q,
    String? supplierId,
    String? brokerId,
    String? catalogItemId,
    String? purchaseFrom,
    String? purchaseTo,
  }) async {
    final s = status?.trim().toLowerCase();
    final statusNorm = (s == null ||
            s.isEmpty ||
            s == 'all' ||
            s == 'undefined' ||
            s == 'null')
        ? null
        : s;
    const allowed = {'draft', 'due_soon', 'overdue', 'paid'};
    final statusParam =
        statusNorm != null && allowed.contains(statusNorm) ? statusNorm : null;

    final want = limit < 1 ? 1 : limit;
    var remaining = want;
    var nextOffset = offset;
    final out = <Map<String, dynamic>>[];

    while (remaining > 0) {
      final pageSize = min(remaining, _kTradePurchasesApiMaxLimit);
      final page = await _listTradePurchasesPage(
        businessId: businessId,
        limit: pageSize,
        offset: nextOffset,
        statusParam: statusParam,
        q: q,
        supplierId: supplierId,
        brokerId: brokerId,
        catalogItemId: catalogItemId,
        purchaseFrom: purchaseFrom,
        purchaseTo: purchaseTo,
      );
      if (page.isEmpty) break;
      out.addAll(page);
      if (page.length < pageSize) break;
      nextOffset += page.length;
      remaining -= page.length;
    }
    return out;
  }

  Future<Map<String, dynamic>?> getTradePurchaseDraft({
    required String businessId,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/businesses/$businessId/trade-purchases/draft',
      );
      final d = res.data;
      if (d == null) return null;
      return Map<String, dynamic>.from(Map<Object?, Object?>.from(d));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      // Draft is optional UX convenience — avoid hard failures when API is
      // temporarily unreachable or slow.
      if (e.response == null) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> putTradePurchaseDraft({
    required String businessId,
    required int step,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/draft',
      data: {'step': step, 'payload': payload},
    );
    return res.data ?? {};
  }

  Future<void> deleteTradePurchaseDraft({required String businessId}) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/trade-purchases/draft',
    );
  }

  Future<Map<String, dynamic>> checkTradePurchaseDuplicate({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/check-duplicate',
      data: body,
    );
    return res.data ?? {};
  }

  /// SSOT line + header totals (non-mutating). Same math as create/persist.
  Future<Map<String, dynamic>> previewTradePurchaseLines({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/preview-lines',
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  /// Full create validation without persisting (`ok` + `errors` + `warnings`).
  Future<Map<String, dynamic>> validateTradePurchase({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/validate',
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  Future<String> nextTradePurchaseHumanId({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/next-human-id',
    );
    final d = res.data ?? {};
    final id = d['human_id']?.toString();
    if (id == null || id.isEmpty) return '';
    return id;
  }

  Future<Map<String, dynamic>> createTradePurchase({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<dynamic>(
      '/v1/businesses/$businessId/trade-purchases',
      data: body,
    );
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> getTradePurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> updateTradePurchase({
    required String businessId,
    required String purchaseId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.put<dynamic>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
      data: body,
    );
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> patchPurchasePayment({
    required String businessId,
    required String purchaseId,
    required double paidAmount,
    String? paidAtIso,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/payment',
      data: {
        'paid_amount': StrictDecimal.fromObject(paidAmount).format(2),
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Marks/unmarks a purchase as delivered (received at warehouse).
  Future<Map<String, dynamic>> markPurchaseDelivered({
    required String businessId,
    required String purchaseId,
    required bool isDelivered,
    String? deliveryNotes,
  }) async {
    final path =
        '/v1/businesses/$businessId/trade-purchases/$purchaseId/delivery';
    final resp = await _dio.patch<dynamic>(
      path,
      data: {
        'is_delivered': isDelivered,
        if (deliveryNotes != null && deliveryNotes.isNotEmpty)
          'delivery_notes': deliveryNotes,
        if (isDelivered) 'delivered_at': DateTime.now().toIso8601String(),
      },
    );
    final d = resp.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> markPurchasePaid({
    required String businessId,
    required String purchaseId,
    double? paidAmount,
    String? paidAtIso,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/mark-paid',
      data: {
        if (paidAmount != null)
          'paid_amount': StrictDecimal.fromObject(paidAmount).format(2),
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> lastTradePurchaseDefaults({
    required String businessId,
    required String catalogItemId,
    String? supplierId,
    String? brokerId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/last-defaults',
      queryParameters: {
        'catalog_item_id': catalogItemId,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> cancelPurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/cancel',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> deleteTradePurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
    );
  }

  Future<Map<String, dynamic>> tradePurchaseSummary({
    required String businessId,
    String? from,
    String? to,
    String? supplierId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-summary',
      queryParameters: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
      },
    );
    return res.data ?? {};
  }

  /// Trade purchase line aggregates (replaces legacy Entry-based `/analytics/items`).
  Future<List<Map<String, dynamic>>> tradeReportItems({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-items',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  Future<List<Map<String, dynamic>>> tradeReportSuppliers({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-suppliers',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  Future<List<Map<String, dynamic>>> tradeReportCategories({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-categories',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  /// Subcategory (CategoryType) spend — matches catalog category → type → items.
  Future<List<Map<String, dynamic>>> tradeReportTypes({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-types',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  /// Per-day line profit sums (SSOT for overview charts; replaces listTradePurchases slicing).
  Future<List<Map<String, dynamic>>> tradeReportDailyProfit({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-daily-profit',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  /// Single call: same definitions as trade reports + nested category line items + mapping recs.
  Future<Map<String, dynamic>> tradeDashboardSnapshot({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-dashboard-snapshot',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Bundled dashboard snapshot for home (`compact` omits heavy keys server-side).
  Future<Map<String, dynamic>> reportsHomeOverview({
    required String businessId,
    required String from,
    required String to,
    bool compact = false,
    bool shellBundle = false,
    int? maxSpanDays,
  }) async {
    final qp = <String, dynamic>{
      'from': from,
      'to': to,
      if (compact) 'compact': true,
      if (shellBundle) 'shell_bundle': true,
      if (maxSpanDays != null) 'max_span_days': maxSpanDays,
    };
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/home-overview',
      queryParameters: qp,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Per (item, supplier, broker) trade stats and best-supplier recommendations (deals≥2 vwap).
  Future<Map<String, dynamic>> tradeSupplierBrokerMap({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-supplier-broker-map',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Latest [TradePurchase] header for [supplierId] (strict DB autofill — no aggregates).
  Future<Map<String, dynamic>> tradeLastSupplierAutofill({
    required String businessId,
    required String supplierId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-last-supplier-autofill',
      queryParameters: {'supplier_id': supplierId},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> getWhatsAppReportSchedule({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/whatsapp-reports/schedule',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> patchWhatsAppReportSchedule({
    required String businessId,
    bool? enabled,
    String? scheduleType, // daily|weekly|monthly
    int? hour,
    int? minute,
    String? timezone,
    String? toE164,
  }) async {
    final data = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (scheduleType != null) 'schedule_type': scheduleType,
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      if (timezone != null) 'timezone': timezone,
      if (toE164 != null) 'to_e164': toE164,
    };
    await _dio.patch<dynamic>(
      '/v1/businesses/$businessId/whatsapp-reports/schedule',
      data: data,
    );
  }

  Future<List<Map<String, dynamic>>> listSuppliers({
    required String businessId,
    /// Smaller JSON (no address/notes); server skips loading those columns.
    bool compact = true,
    /// Only honored when [compact] is true (server cap 5000).
    int? limit,
  }) async {
    final q = <String, dynamic>{};
    if (compact) q['compact'] = 'true';
    if (compact && limit != null) q['limit'] = limit;
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/suppliers',
      queryParameters: q.isEmpty ? null : q,
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createSupplier({
    required String businessId,
    required String name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? brokerId,
    List<String>? brokerIds,
    String? gstNumber,
    String? address,
    String? notes,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    bool aiMemoryEnabled = false,
    Map<String, dynamic>? preferences,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (whatsappNumber != null && whatsappNumber.isNotEmpty)
        'whatsapp_number': whatsappNumber,
      if (location != null && location.isNotEmpty) 'location': location,
      if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      if (brokerIds != null && brokerIds.isNotEmpty) 'broker_ids': brokerIds,
      if (gstNumber != null && gstNumber.isNotEmpty) 'gst_number': gstNumber,
      if (address != null && address.isNotEmpty) 'address': address,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (defaultPaymentDays != null) 'default_payment_days': defaultPaymentDays,
      if (defaultDiscount != null) 'default_discount': defaultDiscount,
      if (defaultDeliveredRate != null)
        'default_delivered_rate': defaultDeliveredRate,
      if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
      if (freightType != null && freightType.isNotEmpty)
        'freight_type': freightType,
      'ai_memory_enabled': aiMemoryEnabled,
    };
    if (preferences != null) {
      final c = preferences['category_ids'];
      final t = preferences['type_ids'];
      final i = preferences['item_ids'];
      if ((c is List && c.isNotEmpty) ||
          (t is List && t.isNotEmpty) ||
          (i is List && i.isNotEmpty)) {
        data['preferences'] = preferences;
      }
    }
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers',
      data: data,
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> listBrokers(
      {required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/brokers');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getSupplier(
      {required String businessId, required String supplierId}) async {
    final res = await _dio
        .get<dynamic>('/v1/businesses/$businessId/suppliers/$supplierId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> getBroker(
      {required String businessId, required String brokerId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/brokers/$brokerId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<List<Map<String, dynamic>>> listBrokerLinkedSuppliers({
    required String businessId,
    required String brokerId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/brokers/$brokerId/linked-suppliers',
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createBroker({
    required String businessId,
    required String name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? notes,
    String commissionType = 'percent',
    double? commissionValue,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (whatsappNumber != null && whatsappNumber.isNotEmpty)
          'whatsapp_number': whatsappNumber,
        if (location != null && location.isNotEmpty) 'location': location,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null && freightType.isNotEmpty)
          'freight_type': freightType,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateSupplier({
    required String businessId,
    required String supplierId,
    String? name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? brokerId,
    List<String>? brokerIds,
    String? gstNumber,
    String? address,
    String? notes,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    bool? aiMemoryEnabled,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
        if (location != null) 'location': location,
        if (brokerId != null) 'broker_id': brokerId,
        if (brokerIds != null) 'broker_ids': brokerIds,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (notes != null) 'notes': notes,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null) 'freight_type': freightType,
        if (aiMemoryEnabled != null) 'ai_memory_enabled': aiMemoryEnabled,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteSupplier(
      {required String businessId, required String supplierId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/suppliers/$supplierId');
  }

  Future<Map<String, dynamic>> updateBroker({
    required String businessId,
    required String brokerId,
    String? name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? notes,
    String? commissionType,
    double? commissionValue,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
        if (commissionType != null) 'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null) 'freight_type': freightType,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteBroker(
      {required String businessId, required String brokerId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/brokers/$brokerId');
  }

  Future<List<Map<String, dynamic>>> listItemCategories(
      {required String businessId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/item-categories');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createItemCategory(
      {required String businessId, required String name}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateItemCategory({
    required String businessId,
    required String categoryId,
    required String name,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<void> deleteItemCategory(
      {required String businessId, required String categoryId}) async {
    await _dio
        .delete<void>('/v1/businesses/$businessId/item-categories/$categoryId');
  }

  Future<List<Map<String, dynamic>>> listCategoryTypes({
    required String businessId,
    required String categoryId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types',
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// All category types with parent category name (single round-trip).
  Future<List<Map<String, dynamic>>> listCategoryTypesIndex({
    required String businessId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/category-types-index',
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createCategoryType({
    required String businessId,
    required String categoryId,
    required String name,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCategoryType({
    required String businessId,
    required String categoryId,
    required String typeId,
    required String name,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types/$typeId',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<void> deleteCategoryType({
    required String businessId,
    required String categoryId,
    required String typeId,
  }) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types/$typeId',
    );
  }

  Future<List<Map<String, dynamic>>> listCatalogItems({
    required String businessId,
    String? categoryId,
    String? typeId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog-items',
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Token-sort fuzzy matches for catalog duplicate hints (create-item UIs).
  Future<List<Map<String, dynamic>>> catalogFuzzyCheck({
    required String businessId,
    required String name,
    String? supplierId,
    String? categoryId,
    String? typeId,
  }) async {
    final q = name.trim();
    if (q.isEmpty) return [];
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog/fuzzy-check',
      queryParameters: {
        'name': q,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
      },
    );
    final data = res.data;
    if (data is! Map) return [];
    final hits = data['hits'];
    if (hits is! List) return [];
    return hits
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> createCatalogItem({
    required String businessId,
    required String categoryId,
    required String name,
    required String defaultUnit,
    required List<String> defaultSupplierIds,
    String? hsnCode,
    String? itemCode,
    String? typeId,
    double? defaultKgPerBag,
    double? defaultItemsPerBox,
    double? defaultWeightPerTin,
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
    List<String> defaultBrokerIds = const [],
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items',
      data: {
        'category_id': categoryId,
        'name': name,
        'default_unit': defaultUnit,
        'default_supplier_ids': defaultSupplierIds,
        if (defaultBrokerIds.isNotEmpty) 'default_broker_ids': defaultBrokerIds,
        if (hsnCode != null && hsnCode.trim().isNotEmpty) 'hsn_code': hsnCode.trim(),
        if (itemCode != null && itemCode.trim().isNotEmpty) 'item_code': itemCode.trim(),
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
        if (defaultKgPerBag != null && defaultKgPerBag > 0)
          'default_kg_per_bag': defaultKgPerBag,
        if (defaultItemsPerBox != null && defaultItemsPerBox > 0)
          'default_items_per_box': defaultItemsPerBox,
        if (defaultWeightPerTin != null && defaultWeightPerTin > 0)
          'default_weight_per_tin': defaultWeightPerTin,
        if (defaultPurchaseUnit != null && defaultPurchaseUnit.isNotEmpty)
          'default_purchase_unit': defaultPurchaseUnit,
        if (defaultSaleUnit != null && defaultSaleUnit.isNotEmpty)
          'default_sale_unit': defaultSaleUnit,
        if (taxPercent != null) 'tax_percent': taxPercent,
        if (defaultLandingCost != null) 'default_landing_cost': defaultLandingCost,
        if (defaultSellingCost != null) 'default_selling_cost': defaultSellingCost,
      },
    );
    return res.data ?? {};
  }

  /// Batch-create catalog items (same shape as `CatalogBatchItemIn`).
  Future<Map<String, dynamic>> createCatalogItemsBatch({
    required String businessId,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/batch',
      data: {'items': items},
    );
    return res.data ?? {};
  }

  /// ZIP of `purchases.csv` + README for the selected preset (month / quarter / all).
  Future<Uint8List> downloadBusinessBackup({
    required String businessId,
    String rangePreset = 'month',
  }) async {
    final res = await _dio.post<List<int>>(
      '/v1/businesses/$businessId/exports/backup',
      data: {'range_preset': rangePreset},
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final raw = res.data;
    if (raw == null) return Uint8List(0);
    return Uint8List.fromList(raw);
  }

  Future<Map<String, dynamic>> supplierPurchaseDefaults({
    required String businessId,
    required String supplierId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/supplier-purchase-defaults',
      queryParameters: {'supplier_id': supplierId},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getCatalogItem(
      {required String businessId, required String itemId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/v1/businesses/$businessId/catalog-items/$itemId');
    return res.data ?? {};
  }

  /// Stock list with filters (server-side pagination).
  Future<Map<String, dynamic>> listStock({
    required String businessId,
    int page = 1,
    int perPage = 50,
    String q = '',
    String category = '',
    String subcategory = '',
    String status = 'all',
    String sort = 'name',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/list',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'q': q,
        'category': category,
        'subcategory': subcategory,
        'status': status,
        'sort': sort,
      },
    );
    return res.data ??
        <String, dynamic>{
          'items': <dynamic>[],
          'total': 0,
          'page': page,
          'per_page': perPage,
        };
  }

  /// On-hand warehouse valuation (landing cost × qty) and unit buckets.
  Future<Map<String, dynamic>> stockInventorySummary({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/inventory-summary',
    );
    return res.data ??
        <String, dynamic>{
          'total_value_inr': 0,
          'bags': 0,
          'boxes': 0,
          'tins': 0,
          'kg': 0,
          'item_count': 0,
        };
  }

  /// Low-stock list (current below reorder when reorder is set), sorted by urgency.
  Future<Map<String, dynamic>> listStockLow({
    required String businessId,
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/low',
      queryParameters: {
        'page': page,
        'per_page': perPage,
      },
    );
    return res.data ??
        <String, dynamic>{
          'items': <dynamic>[],
          'total': 0,
          'page': page,
          'per_page': perPage,
        };
  }

  Future<List<Map<String, dynamic>>> listStockAuditRecent({
    required String businessId,
    int limit = 12,
    /// Calendar day filter (YYYY-MM-DD). Omit for latest across all days.
    String? on,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/stock/audit/recent',
      queryParameters: {
        'limit': limit,
        if (on != null && on.isNotEmpty) 'on': on,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) e
        else if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// Today's stock count variances (purchase qty vs verification).
  Future<List<Map<String, dynamic>>> listStockVariancesToday({
    required String businessId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/stock/variances/today',
    );
    final data = res.data;
    if (data is! List) return [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) e
        else if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<List<Map<String, dynamic>>> listActiveSessions({
    required String businessId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/users/active-sessions',
    );
    final data = res.data;
    if (data is! List) return [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) e
        else if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// Resolve catalog item by barcode / item code.
  Future<Map<String, dynamic>> barcodeStockLookup({
    required String businessId,
    required String code,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/barcode/lookup',
      queryParameters: {'code': code.trim()},
    );
    return res.data ?? {};
  }

  /// Stock + recent purchases for one item.
  Future<Map<String, dynamic>> getStockItem({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/$itemId',
    );
    return res.data ?? {};
  }

  /// Alert owners/managers about a catalog item (in-app notifications).
  Future<void> notifyOwnerStockItem({
    required String businessId,
    required String itemId,
  }) async {
    await _dio.post<void>(
      '/v1/businesses/$businessId/stock/$itemId/notify-owner',
    );
  }

  /// Add item to business reorder list (pending).
  Future<void> addItemToReorderList({
    required String businessId,
    required String itemId,
  }) async {
    await _dio.post<void>(
      '/v1/businesses/$businessId/stock/$itemId/reorder',
    );
  }

  Future<List<Map<String, dynamic>>> listReorderEntries({
    required String businessId,
    String status = 'pending',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/reorder',
      queryParameters: {'status': status},
    );
    final data = res.data;
    final items = data?['items'];
    if (items is! List) return [];
    return [for (final e in items) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<Map<String, dynamic>> patchReorderEntry({
    required String businessId,
    required String entryId,
    required String status,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/reorder/$entryId',
      data: {'status': status},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> deleteReorderEntry({
    required String businessId,
    required String entryId,
  }) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/stock/reorder/$entryId',
    );
  }

  /// Authoritative stock adjustment (audit logged on server).
  Future<List<Map<String, dynamic>>> listStockAuditForItem({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/businesses/$businessId/stock/audit/$itemId',
    );
    return _parseJsonMapList(res.data);
  }

  Future<Map<String, dynamic>> patchStockItem({
    required String businessId,
    required String itemId,
    required num newQty,
    String adjustmentType = 'verification',
    String? reason,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/$itemId',
      data: {
        'new_qty': newQty,
        'adjustment_type': adjustmentType,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getBarcodeLabel({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/barcode/$itemId',
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> barcodeLabelBatch({
    required String businessId,
    required List<String> itemIds,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/barcode/batch',
      data: {'item_ids': itemIds},
    );
    final labels = res.data?['labels'];
    if (labels is List) {
      return labels
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  /// Trade purchases only: latest price per supplier, last five landed prices, avg.
  Future<Map<String, dynamic>> catalogItemTradeSupplierPrices({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/trade-supplier-prices',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCatalogItem({
    required String businessId,
    required String itemId,
    String? categoryId,
    String? typeId,
    bool patchTypeId = false,
    String? name,
    String? defaultUnit,
    bool includeDefaultUnit = false,
    bool patchDefaultKgPerBag = false,
    double? defaultKgPerBag,
    bool patchDefaultItemsPerBox = false,
    double? defaultItemsPerBox,
    bool patchDefaultWeightPerTin = false,
    double? defaultWeightPerTin,
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    String? hsnCode,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
    List<String>? defaultSupplierIds,
    List<String>? defaultBrokerIds,
  }) async {
    final data = <String, dynamic>{
      if (categoryId != null) 'category_id': categoryId,
      if (patchTypeId) 'type_id': typeId,
      if (name != null) 'name': name,
    };
    if (includeDefaultUnit) {
      data['default_unit'] = defaultUnit;
    } else if (defaultUnit != null) {
      data['default_unit'] = defaultUnit;
    }
    if (patchDefaultKgPerBag) {
      data['default_kg_per_bag'] = defaultKgPerBag;
    }
    if (patchDefaultItemsPerBox) {
      data['default_items_per_box'] = defaultItemsPerBox;
    }
    if (patchDefaultWeightPerTin) {
      data['default_weight_per_tin'] = defaultWeightPerTin;
    }
    if (defaultPurchaseUnit != null) {
      data['default_purchase_unit'] = defaultPurchaseUnit;
    }
    if (defaultSaleUnit != null) {
      data['default_sale_unit'] = defaultSaleUnit;
    }
    if (hsnCode != null) {
      data['hsn_code'] = hsnCode.isEmpty ? null : hsnCode;
    }
    if (taxPercent != null) {
      data['tax_percent'] = taxPercent;
    }
    if (defaultLandingCost != null) {
      data['default_landing_cost'] = defaultLandingCost;
    }
    if (defaultSellingCost != null) {
      data['default_selling_cost'] = defaultSellingCost;
    }
    if (defaultSupplierIds != null) {
      data['default_supplier_ids'] = defaultSupplierIds;
    }
    if (defaultBrokerIds != null) {
      data['default_broker_ids'] = defaultBrokerIds;
    }
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId',
      data: data,
    );
    return res.data ?? {};
  }

  Future<void> deleteCatalogItem(
      {required String businessId, required String itemId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/catalog-items/$itemId');
  }

  Future<Map<String, dynamic>> catalogItemInsights({
    required String businessId,
    required String itemId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> categoryInsights({
    required String businessId,
    required String categoryId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  /// Confirmed trade aggregates per item in a category (decision dashboard).
  Future<Map<String, dynamic>> categoryTradeSummary({
    required String businessId,
    required String categoryId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/trade-summary',
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> catalogItemLines({
    required String businessId,
    required String itemId,
    required String from,
    required String to,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog-items/$itemId/lines',
      queryParameters: {
        'from': from,
        'to': to,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listCatalogVariants({
    required String businessId,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/v1/businesses/$businessId/catalog-items/$itemId/variants',
      );
      final data = res.data;
      if (data is! List) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      // Current server returns 200 (maybe empty). A 404 here usually means the
      // running API is older than this client (route not registered) — treat as no variants.
      if (e.response?.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCatalogVariant({
    required String businessId,
    required String itemId,
    required String name,
    double? defaultKgPerBag,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/variants',
      data: {
        'name': name,
        if (defaultKgPerBag != null) 'default_kg_per_bag': defaultKgPerBag,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCatalogVariant({
    required String businessId,
    required String variantId,
    String? name,
    double? defaultKgPerBag,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-variants/$variantId',
      data: {
        if (name != null) 'name': name,
        if (defaultKgPerBag != null) 'default_kg_per_bag': defaultKgPerBag,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteCatalogVariant(
      {required String businessId, required String variantId}) async {
    await _dio
        .delete<void>('/v1/businesses/$businessId/catalog-variants/$variantId');
  }

  Future<Map<String, dynamic>> contactsSearch({
    required String businessId,
    required String query,
    String? scope,
  }) async {
    final qp = <String, dynamic>{'q': query};
    if (scope != null && scope.trim().isNotEmpty) {
      qp['scope'] = scope.trim();
    }
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/contacts/search',
      queryParameters: qp,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> supplierMetrics({
    required String businessId,
    required String supplierId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId/metrics',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> brokerMetrics({
    required String businessId,
    required String brokerId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId/metrics',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> categoryItems({
    required String businessId,
    required String category,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/contacts/category-items',
      queryParameters: {'category': category, 'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Legacy entry-based home KPIs (top item profit, MTD vs prior month, alerts).
  Future<Map<String, dynamic>> homeInsights({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> analyticsItems(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsCategories(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/categories',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsSuppliers(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/suppliers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Per-supplier item breakdown (for expandable supplier rows in Reports).
  Future<List<Map<String, dynamic>>> analyticsSupplierItems({
    required String businessId,
    required String supplierId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/suppliers/$supplierId/items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsBrokers(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/brokers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> priceIntelligence({
    required String businessId,
    required String item,
    double? currentPrice,
    int windowDays = 90,
    String priceField = 'landing',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/price-intelligence',
      queryParameters: {
        'item': item,
        if (currentPrice != null) 'current_price': currentPrice,
        'window_days': windowDays,
        'price_field': priceField,
      },
    );
    return res.data ?? {};
  }

  /// OCR preview stub — requires `ENABLE_OCR` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaOcrPreview({
    required String businessId,
    String imageBase64 = '',
    String? pasteText,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/ocr',
      data: {
        'image_base64': imageBase64,
        if (pasteText != null && pasteText.trim().isNotEmpty) 'paste_text': pasteText.trim(),
      },
    );
    return res.data ?? {};
  }

  /// Voice/STT preview stub — requires `ENABLE_VOICE` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaVoicePreview(
      {required String businessId, String audioBase64 = 'QQ=='}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/voice',
      data: {'audio_base64': audioBase64},
    );
    return res.data ?? {};
  }

  /// In-app assistant — preview → confirm; optional [previewToken] + [entryDraft] for YES/NO.
  ///
  /// Uses a longer receive timeout (LLM cold start) and retries transient network / gateway errors.
  Future<Map<String, dynamic>> aiChat({
    required String businessId,
    required List<Map<String, dynamic>> messages,
    String? previewToken,
    Map<String, dynamic>? entryDraft,
  }) async {
    final path = '/v1/businesses/$businessId/ai/chat';
    final data = <String, dynamic>{
      'messages': messages,
      if (previewToken != null) 'preview_token': previewToken,
      if (entryDraft != null) 'entry_draft': entryDraft,
    };
    const receive = Duration(seconds: 120);
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          path,
          data: data,
          options: Options(receiveTimeout: receive),
        );
        return res.data ?? {};
      } on DioException catch (e) {
        lastError = e;
        final canRetry = attempt < maxAttempts - 1 && _retryableAssistantRequest(e);
        if (!canRetry) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 320 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('aiChat: no attempt');
  }

  /// Structured intent JSON (server-side; increments usage counter when AI enabled).
  Future<Map<String, dynamic>> aiIntent({
    required String businessId,
    required String text,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/ai/intent',
      data: {'text': text},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingStatus(
      {required String businessId}) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/v1/businesses/$businessId/billing/status');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingQuote({
    required String businessId,
    String planCode = 'basic',
    bool whatsappAddon = false,
    bool aiAddon = false,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/quote',
      queryParameters: {
        'plan_code': planCode,
        'whatsapp_addon': whatsappAddon,
        'ai_addon': aiAddon,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingCreateOrder({
    required String businessId,
    String planCode = 'basic',
    bool whatsappAddon = false,
    bool aiAddon = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/create-order',
      data: {
        'plan_code': planCode,
        'whatsapp_addon': whatsappAddon,
        'ai_addon': aiAddon,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingVerify({
    required String businessId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/verify',
      data: {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
    );
    return res.data ?? {};
  }

  /// Monthly cloud / infra line (Settings + Home card).
  Future<Map<String, dynamic>> getCloudCost({required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/cloud-cost');
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }

  Future<Map<String, dynamic>> patchCloudCost({
    required String businessId,
    String? name,
    double? amountInr,
    int? dueDay,
  }) async {
    final res = await _dio.patch<dynamic>(
      '/v1/businesses/$businessId/cloud-cost',
      data: {
        if (name != null) 'name': name,
        if (amountInr != null) 'amount_inr': amountInr,
        if (dueDay != null) 'due_day': dueDay,
      },
    );
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }

  Future<Map<String, dynamic>> postCloudCostPay({
    required String businessId,
    double? amountInr,
    String? paymentId,
    String? provider,
  }) async {
    final res = await _dio.post<dynamic>(
      '/v1/businesses/$businessId/cloud-cost/pay',
      data: {
        if (amountInr != null) 'amount_inr': amountInr,
        if (paymentId != null && paymentId.isNotEmpty) 'payment_id': paymentId,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }
}
