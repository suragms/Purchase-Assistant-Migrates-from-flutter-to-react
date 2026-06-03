import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../api/fastapi_error.dart';
import '../config/app_config.dart';

bool _blobLooksLikeConnectionRefused(String blob) {
  final lower = blob.toLowerCase();
  return lower.contains('connection refused') ||
      lower.contains('err_connection_refused') ||
      lower.contains('active refused') ||
      lower.contains('failed to connect');
}

/// Chrome/Edge: Wi‑Fi ↔ mobile, VPN toggle, sleep/wake — not an app bug.
bool dioBlobLooksLikeTransientNetwork(String blob) {
  final lower = blob.toLowerCase();
  return lower.contains('err_network_changed') ||
      lower.contains('network_changed') ||
      lower.contains('err_internet_disconnected') ||
      lower.contains('internet_disconnected') ||
      lower.contains('err_quic_protocol') ||
      lower.contains('quic_protocol_error') ||
      lower.contains('err_http2_protocol') ||
      lower.contains('http2_protocol_error');
}

String? _transientNetworkChangeHint(String blob) {
  if (!dioBlobLooksLikeTransientNetwork(blob)) return null;
  final lower = blob.toLowerCase();
  if (lower.contains('internet_disconnected')) {
    return 'You appear to be offline. Check your network and try again.';
  }
  if (lower.contains('quic') || lower.contains('http2_protocol')) {
    return 'Connection was interrupted while loading data. Try again in a moment.';
  }
  return 'Your connection changed (Wi‑Fi or mobile). Wait a moment and try again.';
}

/// When the browser cannot open a TCP connection to the API (backend not running / wrong host).
String? _connectionUnreachableHint(DioException e) {
  final blob = '${e.message} ${e.error}';
  final lower = blob.toLowerCase();
  if (_blobLooksLikeConnectionRefused(blob)) {
    if (kDebugMode || AppConfig.apiBasePointsToLoopback) {
      return 'Cannot reach the API (connection refused). For local development, '
          'start the backend on port 8000 and open the app from the same host '
          '(e.g. localhost with localhost, or 127.0.0.1 with 127.0.0.1).';
    }
    return 'Cannot reach the server. It may be temporarily unavailable—try again shortly.';
  }
  // Distinguish timeout vs offline: a slow server is not "no internet".
  if (lower.contains('connection timed out') ||
      lower.contains('timed out') ||
      lower.contains('took longer') ||
      lower.contains('deadline exceeded') ||
      lower.contains('receive timeout') ||
      lower.contains('send timeout')) {
    return 'Request timed out. The server may be slow or your connection is unstable—try again.';
  }
  if (lower.contains('network is unreachable')) {
    return 'You appear to be offline. Check your network and try again.';
  }
  if (lower.contains('connection reset')) {
    return 'Connection was interrupted. Try again.';
  }
  final transient = _transientNetworkChangeHint(blob);
  if (transient != null) return transient;
  return null;
}

/// Web-only: Dio often reports CORS / fetch failures as unknown + empty body.
String? _webBrowserNetworkHint(DioException e) {
  final blob = '${e.message} ${e.error}'.toLowerCase();
  final transient = _transientNetworkChangeHint(blob);
  if (transient != null) return transient;
  if (blob.contains('failed to fetch') ||
      blob.contains('xmlhttprequest') ||
      blob.contains('networkerror') ||
      blob.contains('clientexception') ||
      blob.contains('load failed') ||
      blob.contains('err_network') ||
      blob.contains('cors')) {
    return 'Cannot reach the server (network/CORS). Check your connection and try again.';
  }
  return null;
}

/// True when the failure is a transport/connection error (no HTTP response) — for inline Retry UI.
bool isDioNoConnectionError(DioException e) {
  if (e.type == DioExceptionType.badResponse) return false;
  if (e.response != null) return false;
  final t = e.type;
  if (t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout ||
      t == DioExceptionType.receiveTimeout ||
      t == DioExceptionType.connectionError) {
    return true;
  }
  if (t == DioExceptionType.unknown && e.response == null) {
    return true;
  }
  return false;
}

/// Safe GET retry after Wi‑Fi/mobile handoff (Chrome `ERR_NETWORK_CHANGED`).
bool dioIsAutoRetryableTransport(DioException e) {
  if (e.requestOptions.extra['skipAutoRetry'] == true) return false;
  if (e.response != null) return false;
  final t = e.type;
  if (t == DioExceptionType.connectionError ||
      t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout ||
      t == DioExceptionType.receiveTimeout) {
    return true;
  }
  if (t == DioExceptionType.unknown) {
    return dioBlobLooksLikeTransientNetwork('${e.message} ${e.error}');
  }
  return false;
}

/// For bill scan uploads: do **not** treat read/write timeouts as "offline".
/// Queue offline only when the transport layer cannot connect.
bool shouldQueueScanOffline(DioException e) {
  if (e.type == DioExceptionType.badResponse) return false;
  if (e.response != null) return false;
  if (e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout) {
    return false;
  }
  return e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      (e.type == DioExceptionType.unknown && e.response == null);
}

/// User-safe copy for auth and network failures (no URLs, env names, or raw exceptions).
String friendlyAuthError(
  Object error, {
  required AuthErrorContext context,
}) {
  if (error is DioException) {
    // Reachability first: no HTTP body / wrong host / API stopped — not "wrong password".
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) return hint;
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) return web;
        return 'Cannot complete the request. Check your network and try again.';
      }
      return 'Cannot complete the request. Check your network and try again.';
    }

    final sc = error.response?.statusCode;
    if (sc == 401) {
      if (context == AuthErrorContext.register) {
        return 'Could not create your account. Check your details and try again.';
      }
      return 'Wrong username, phone, or password. Try again.';
    }
    if (sc == 400 || sc == 422) {
      return context == AuthErrorContext.register
          ? 'Please check your details and try again.'
          : 'Something was not right with that sign-in. Try again.';
    }
    if (sc == 409) {
      return context == AuthErrorContext.register
          ? 'This email is already registered. Sign in instead, or use a different email.'
          : 'That email or username is already taken.';
    }
    if (sc == 503) {
      return 'Sign-in is temporarily unavailable. Try again in a moment.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
  }
  return 'Something went wrong. Please try again.';
}

String friendlyGoogleSignInError(Object error) {
  if (error is DioException) {
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) {
        return '$hint You can use email sign-in instead.';
      }
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) {
          return '$web You can use email sign-in instead.';
        }
        return 'Cannot complete the request. Try email sign-in, or try again later.';
      }
      return 'Cannot complete the request. Check your network and try again.';
    }

    final sc = error.response?.statusCode;
    if (sc == 401) {
      return 'Google sign-in could not be verified. Try email sign-in instead.';
    }
    if (sc == 503) {
      return 'Sign-in is temporarily unavailable. Try again in a moment.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
  }
  return 'Google sign-in did not work. Try again or use email sign-in.';
}

bool _isNetworkError(DioException e) {
  // badResponse = HTTP error status; never treat as "offline" (even if body is empty).
  if (e.type == DioExceptionType.badResponse) return false;
  if (e.response != null) return false;
  final t = e.type;
  return t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout ||
      t == DioExceptionType.receiveTimeout ||
      t == DioExceptionType.connectionError ||
      (t == DioExceptionType.unknown && e.response == null);
}

enum AuthErrorContext { login, register }

/// Banner title: distinguish "no Wi‑Fi" from "API not listening" (common on Flutter web + localhost).
String authUnreachableBannerTitle(DioException? e) {
  if (e == null) return "Can't reach server";
  final b = '${e.message} ${e.error}';
  if (_blobLooksLikeConnectionRefused(b)) {
    return 'API not reachable';
  }
  return 'Connection problem';
}

String? authServerUnreachableDetail(DioException? e) {
  if (e == null) return null;
  final b = '${e.message} ${e.error}';
  if (_blobLooksLikeConnectionRefused(b)) {
    if (kDebugMode || AppConfig.apiBasePointsToLoopback) {
      return 'Nothing is listening on port 8000 (connection refused). '
          'Start the API from the backend folder, e.g. '
          'uvicorn app.main:app --reload --host 127.0.0.1 --port 8000. '
          'Production builds must set API_BASE_URL to your real HTTPS API when you run '
          'flutter build web.';
    }
    return 'The app could not reach your server. If you are the administrator, '
        'confirm the API URL used for this deployment.';
  }
  if (b.toLowerCase().contains('timed out') ||
      b.toLowerCase().contains('network is unreachable')) {
    return 'Check your network, firewall, and VPN, then try again.';
  }
  return null;
}

/// Short user-facing copy for failed API calls in SnackBars and dialogs (no stack traces or raw response dumps).
///
/// Set [forAssistant] for the in-app Assistant tab — clearer copy when the LLM endpoint fails.
String friendlyApiError(Object error, {bool forAssistant = false}) {
  if (error is DioException) {
    final sc = error.response?.statusCode;
    if (sc == 402) {
      return forAssistant
          ? 'Monthly AI token limit reached for this business. Try again next month or ask the owner.'
          : 'Monthly AI usage limit reached. Ask your owner or try again next month.';
    }
    if (sc == 401 || sc == 403) {
      return forAssistant
          ? 'Assistant could not verify your session. Open Settings or sign in again.'
          : 'Session expired. Please sign in again.';
    }
    if (sc == 404) {
      return 'This item was not found.';
    }
    if (sc == 408) {
      return 'Request timed out. Please try again.';
    }
    if (sc == 429) {
      return 'Too many requests. Wait a moment and try again.';
    }
    if (sc == 409) {
      final resp = error.response?.data;
      if (resp is Map) {
        final detail = resp['detail'];
        if (detail is String && detail.trim() == 'integrity_error') {
          return 'Stock save was blocked by server audit settings. '
              'Ask the owner to run the latest database update, then try again.';
        }
        if (detail is Map) {
          final code = detail['code']?.toString();
          final raw = detail['message']?.toString() ?? '';
          final msg = raw.trim();
          if (msg.isNotEmpty) {
            if (code == 'DUPLICATE_PURCHASE_DETECTED') {
              return 'Duplicate purchase: similar entry exists for this date.';
            }
            if (code == 'STALE_STOCK_VERSION') {
              return 'Stock changed while you were editing. Refresh and try again.';
            }
            const cap = 420;
            return msg.length <= cap ? msg : '${msg.substring(0, cap)}…';
          }
        }
      }
      return 'Someone else updated this item. Please refresh and try again.';
    }
    if (sc == 400 || sc == 422) {
      // Prefer the domain-aware mapper (e.g. `Line 2: quantity must be > 0`);
      // fall back to the raw FastAPI detail, then a generic copy.
      final friendly = fastApiPurchaseFriendlyError(error.response?.data);
      final detail = friendly ?? fastApiDetailString(error.response?.data);
      if (detail != null && detail.isNotEmpty) {
        const cap = 420;
        return detail.length <= cap ? detail : '${detail.substring(0, cap)}…';
      }
      return 'Please check your input and try again.';
    }
    if (sc == 503) {
      if (AppConfig.apiBasePointsToLoopback && !forAssistant) {
        return 'Local API database is unavailable. Stop any old API on port 8000, '
            'then start it from the backend folder with SQLite '
            '(HEXA_USE_SQLITE=1, DATABASE_URL=sqlite+aiosqlite:///./hexa_dev.db).';
      }
      return forAssistant
          ? 'Assistant is temporarily unavailable. Try again in a moment.'
          : 'Server is starting up. Retrying automatically…';
    }
    if (sc != null && sc >= 500) {
      return forAssistant
          ? 'Assistant hit a server error. Please try again in a moment.'
          : 'Something went wrong on our side. Please try again.';
    }
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) {
        return forAssistant
            ? "Assistant couldn't reach the server. $hint"
            : 'No connection. Changes will sync when online.';
      }
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return forAssistant
            ? 'The assistant request timed out. Try again in a moment.'
            : 'No connection. Changes will sync when online.';
      }
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) {
          return forAssistant
              ? "Assistant couldn't reach the server. $web"
              : 'No connection. Changes will sync when online.';
        }
      }
      return forAssistant
          ? "Can't reach the assistant. Check your connection and try again."
          : 'No connection. Changes will sync when online.';
    }
    return 'Something went wrong. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}
