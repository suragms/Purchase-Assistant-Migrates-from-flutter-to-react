import 'package:dio/dio.dart';

import '../widgets/friendly_load_error.dart';
import 'user_facing_errors.dart';

/// User-safe subtitle for full-screen / card load failures (no stack traces).
String loadStateErrorSubtitle(Object? error) {
  if (error == null) return kFriendlyLoadNetworkSubtitle;

  if (error is DioException) {
    final sc = error.response?.statusCode;
    switch (sc) {
      case 400:
      case 422:
        return 'Invalid request. Please check your input.';
      case 401:
        return 'Session expired. Please log in again.';
      case 403:
        return "You don't have permission for this.";
      case 404:
        return 'Not found.';
      case 503:
        return 'Server error. Please try again shortly.';
      default:
        if (sc != null && sc >= 500) {
          return 'Server error. Please try again shortly.';
        }
    }
    if (error.response == null) {
      return 'No connection. Check your network and try again.';
    }
    final friendly = userFacingError(error);
    if (friendly.length <= 160) return friendly;
    return '${friendly.substring(0, 157)}…';
  }

  return kFriendlyLoadNetworkSubtitle;
}
