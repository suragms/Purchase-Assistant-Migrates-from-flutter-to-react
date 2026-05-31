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
      case 402:
        return 'Monthly AI usage limit reached. Contact your owner or try again next month.';
      case 403:
        return "You don't have permission for this.";
      case 404:
        return 'Not found.';
      case 408:
        return 'Request timed out. Please try again.';
      case 409:
        return 'That conflicts with existing data. Try again.';
      case 429:
        return 'Too many requests. Wait a moment and try again.';
      case 503:
        return 'Server is starting up — wait about 30 seconds, then tap Retry.';
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
