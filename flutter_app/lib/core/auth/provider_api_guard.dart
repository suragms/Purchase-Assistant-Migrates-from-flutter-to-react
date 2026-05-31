import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_failure_policy.dart';
import 'session_notifier.dart' show activeSessionProvider;

/// Skip network fetches when logged out or after terminal 401 (stops request storms).
/// Accepts provider [Ref] and widget [WidgetRef] (different types in Riverpod 2.6).
bool providerSkipApi(dynamic ref) {
  if (ref.read(authSessionExpiredProvider)) return true;
  return ref.read(activeSessionProvider) == null;
}
