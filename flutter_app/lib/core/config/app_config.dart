import 'package:flutter/foundation.dart' show kIsWeb;

import '../theme/hexa_colors.dart';

/// API base URL. Override at run time:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
/// - Web/desktop: http://127.0.0.1:8000 (default; override with API_BASE_URL)
/// - Android emulator: http://10.0.2.2:8000
class AppConfig {
  AppConfig._();

  /// Default product name (store listing / package name are separate).
  static const String appName = HexaColors.appName;

  /// Vercel web builds: set `API_BASE_URL` in project env (see `scripts/vercel-flutter-build.sh`).
  /// If `POST /v1/me/bootstrap-workspace` returns **404**, the client is not hitting the
  /// current backend process (wrong port, stale uvicorn) — fix the URL and restart the API;
  /// the app treats 404/501 on that route as non-fatal and continues.
  /// Default uses 127.0.0.1 (not `localhost`) so Windows resolves IPv4 consistently with uvicorn
  /// bound to 127.0.0.1 and avoids ERR_CONNECTION_REFUSED when `localhost` maps to ::1 only.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Dio base URL for HTTP calls. On **web**, when [apiBaseUrl] targets local port 8000 and the app
  /// is opened on loopback (e.g. `http://localhost:8080`), this returns `http://localhost:8000`
  /// so the browser **Origin** matches the API host (`localhost` vs `127.0.0.1` are different
  /// origins and can break credentialed / CORS flows when mismatched).
  static String get resolvedApiBaseUrl {
    if (!kIsWeb) return apiBaseUrl;
    final page = Uri.base;
    final ph = page.host;
    final pageLoopback =
        ph == 'localhost' || ph == '127.0.0.1' || ph == '::1';
    if (!pageLoopback) return apiBaseUrl;

    final target = Uri.tryParse(apiBaseUrl);
    if (target == null || !target.hasScheme || !target.hasAuthority) {
      return '${page.scheme}://${page.host}:8000';
    }
    final loopbackHost = target.host == 'localhost' ||
        target.host == '127.0.0.1' ||
        target.host == '::1';
    if (!loopbackHost) return apiBaseUrl;

    // Dev hardening:
    // If web app runs on local dev ports (3000/5173/808x/809x/810x) and API_BASE_URL
    // accidentally points to the same frontend port, force API to loopback :8000.
    // This prevents "all loading" + long Dio timeouts + auth refresh loops.
    const likelyFrontendPorts = <int>{
      3000,
      5173,
      5174,
      5175,
      8080,
      8081,
      8082,
      8090,
      8091,
      8092,
      8100,
      8111,
    };
    if (target.port != 8000 &&
        (target.port == page.port || likelyFrontendPorts.contains(target.port))) {
      return '${page.scheme}://${page.host}:8000';
    }

    if (target.port != 8000) return apiBaseUrl;
    return '${page.scheme}://${page.host}:8000';
  }

  /// Web OAuth 2.0 client ID from Google Cloud Console (used as `serverClientId` on iOS/Android so
  /// the ID token audience matches the backend). For Flutter web, also pass as `clientId`.
  /// Build: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const String googleOAuthClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: '',
  );

  /// True when [apiBaseUrl] targets this machine (typical local dev). Used for
  /// user-facing copy: "start the API" vs generic offline messaging.
  static bool get apiBasePointsToLoopback {
    final h = Uri.tryParse(apiBaseUrl)?.host.toLowerCase() ?? '';
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  /// UPI VPA for cloud-cost “Pay via UPI” (optional). Build with:
  /// `--dart-define=CLOUD_UPI_VPA=merchant@ybl --dart-define=CLOUD_UPI_PAYEE_NAME=Your%20Name`
  static const String cloudUpiVpa = String.fromEnvironment(
    'CLOUD_UPI_VPA',
    defaultValue: '',
  );

  static const String cloudUpiPayeeName = String.fromEnvironment(
    'CLOUD_UPI_PAYEE_NAME',
    defaultValue: 'Workspace billing',
  );

  /// Keep in sync with `pubspec.yaml` `version:` (shown in Settings).
  static const String packageVersion = '0.1.4+5';
}
