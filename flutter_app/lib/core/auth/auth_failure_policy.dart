import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True after terminal auth failure — forces router to `/login` even briefly
/// before [sessionProvider] clears.
final authSessionExpiredProvider =
    NotifierProvider<AuthSessionExpiredNotifier, bool>(
  AuthSessionExpiredNotifier.new,
);

class AuthSessionExpiredNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markExpired() => state = true;

  void clear() => state = false;
}

/// Reactive gate: pauses business API on 401 burst / refresh (Riverpod notifies).
class AuthApiGateState {
  const AuthApiGateState({
    this.suspended = false,
    this.circuitOpen = false,
  });

  final bool suspended;
  final bool circuitOpen;

  bool get blockApi => suspended || circuitOpen;
}

/// True while Dio interceptor is refreshing tokens (do not open 401 circuit).
final authRefreshInFlightProvider = StateProvider<bool>((ref) => false);

/// Blocks business API until [SessionNotifier.refreshOnResume] finishes after tab/app resume.
final authResumeGateProvider = StateProvider<bool>((ref) => false);

/// Terminal auth failure — Dio rejects and providers skip until sign-in again.
final authHardBlockApiProvider = Provider<bool>((ref) {
  if (ref.watch(authSessionExpiredProvider)) return true;
  return ref.watch(authApiGateProvider).circuitOpen;
});

/// Soft pause during tab resume / token refresh / 401 suspend (not terminal).
/// Providers may wait via [awaitProviderApiReady]; Dio must still send requests.
final authSoftPauseApiProvider = Provider<bool>((ref) {
  if (ref.watch(authResumeGateProvider)) return true;
  if (ref.watch(authRefreshInFlightProvider)) return true;
  return ref.watch(authApiGateProvider.select((g) => g.suspended));
});

/// Combined pause — used where callers need any auth hold (not Dio layer).
final authBlockApiRequestsProvider = Provider<bool>((ref) {
  if (ref.watch(authHardBlockApiProvider)) return true;
  return ref.watch(authSoftPauseApiProvider);
});

class AuthApiGateNotifier extends Notifier<AuthApiGateState> {
  /// Require several 401s before forced logout — avoids tab-switch storms on web.
  static const _threshold = 4;
  static const _window = Duration(seconds: 15);

  int _count = 0;
  DateTime? _since;

  @override
  AuthApiGateState build() => const AuthApiGateState();

  /// Called synchronously on every business 401 — stops parallel refetch storms.
  void suspendFor401() {
    if (state.suspended && state.circuitOpen) return;
    state = AuthApiGateState(
      suspended: true,
      circuitOpen: state.circuitOpen,
    );
  }

  /// Returns true when the circuit opens (force logout).
  bool record401({bool refreshInFlight = false}) {
    if (refreshInFlight) {
      suspendFor401();
      return false;
    }
    suspendFor401();
    if (state.circuitOpen) return true;

    final now = DateTime.now();
    if (_since == null || now.difference(_since!) > _window) {
      _since = now;
      _count = 0;
    }
    _count++;
    if (_count >= _threshold) {
      state = const AuthApiGateState(suspended: true, circuitOpen: true);
      return true;
    }
    return false;
  }

  void clearSuspend() {
    if (!state.suspended || state.circuitOpen) return;
    state = AuthApiGateState(circuitOpen: state.circuitOpen);
  }

  void reset() {
    _count = 0;
    _since = null;
    state = const AuthApiGateState();
  }

  /// After refresh fails — stop all business API immediately (no 4-strike wait).
  void forceCircuitOpen() {
    _count = _threshold;
    _since = DateTime.now();
    state = const AuthApiGateState(suspended: true, circuitOpen: true);
  }
}

final authApiGateProvider =
    NotifierProvider<AuthApiGateNotifier, AuthApiGateState>(
  AuthApiGateNotifier.new,
);

/// True after a burst of 401s — providers must skip API until sign-in again.
final auth401CircuitOpenProvider = Provider<bool>((ref) {
  if (ref.watch(authSessionExpiredProvider)) return true;
  return ref.watch(authApiGateProvider).circuitOpen;
});

/// Tracks refresh failures to avoid infinite 401 polling on stale tokens.
class AuthRefreshFailureTracker {
  AuthRefreshFailureTracker({this.maxFailures = 2, this.window = const Duration(seconds: 60)});

  final int maxFailures;
  final Duration window;
  final List<DateTime> _transientFailures = [];

  void recordTransientFailure() {
    final now = DateTime.now();
    _transientFailures.removeWhere((t) => now.difference(t) > window);
    _transientFailures.add(now);
  }

  void reset() => _transientFailures.clear();

  bool shouldForceLogout() {
    final now = DateTime.now();
    _transientFailures.removeWhere((t) => now.difference(t) > window);
    return _transientFailures.length >= maxFailures;
  }
}

final authRefreshFailureTrackerProvider = Provider<AuthRefreshFailureTracker>(
  (_) => AuthRefreshFailureTracker(),
);

/// Whether authenticated API calls should run (session present + not expired).
bool authAllowsApiRequests({
  required bool hasSession,
  required bool sessionExpired,
}) =>
    hasSession && !sessionExpired;
