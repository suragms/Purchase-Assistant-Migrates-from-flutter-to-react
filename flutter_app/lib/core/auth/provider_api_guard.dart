import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_foreground_provider.dart';
import 'auth_failure_policy.dart';
import 'session_notifier.dart' show activeSessionProvider;

/// Root [ProviderContainer] for staggered invalidations after async gaps.
ProviderContainer? rootProviderContainer;

void registerRootProviderContainer(ProviderContainer container) {
  rootProviderContainer = container;
}

/// Resolve container from provider [Ref] or the app root container.
ProviderContainer resolveInvalidationContainer(dynamic ref) {
  if (ref is Ref) return ref.container;
  final root = rootProviderContainer;
  if (root != null) return root;
  throw StateError('No ProviderContainer for invalidation');
}

/// Thrown when an async provider body completes after auto-dispose (benign).
class ProviderFetchAborted implements Exception {
  const ProviderFetchAborted();
}

/// Tracks disposal during async provider bodies.
class ProviderDisposeGuard {
  bool disposed = false;
}

void safeRefOnDispose(dynamic ref, void Function() cb) {
  try {
    ref.onDispose(cb);
  } catch (_) {
    // Provider already torn down — treat as disposed.
  }
}

ProviderDisposeGuard registerProviderDisposeGuard(dynamic ref) {
  final guard = ProviderDisposeGuard();
  safeRefOnDispose(ref, () => guard.disposed = true);
  return guard;
}

bool providerWasDisposed(ProviderDisposeGuard guard) => guard.disposed;

void registerProviderKeepAliveTimer(dynamic ref, Duration ttl) {
  try {
    final link = ref.keepAlive();
    final timer = Timer(ttl, link.close);
    safeRefOnDispose(ref, timer.cancel);
  } catch (_) {}
}

/// Skip network fetches when logged out or after terminal 401 (stops request storms).
/// Accepts provider [Ref] and widget [WidgetRef] (different types in Riverpod 2.6).
/// Resume-gate / refresh-in-flight pauses are handled by [awaitProviderApiReady], not here.
bool providerSkipApi(dynamic ref) {
  if (ref.read(authHardBlockApiProvider)) return true;
  if (!ref.read(appForegroundProvider)) return true;
  if (ref.read(activeSessionProvider) == null) return true;
  return false;
}

bool providerAuthSoftPaused(dynamic ref) => ref.read(authSoftPauseApiProvider);

/// Clear resume/refresh gates stuck after IndexedStack tab switches (web shell).
void clearStuckAuthGates(dynamic ref) {
  try {
    ref.read(authResumeGateProvider.notifier).state = false;
    ref.read(authRefreshInFlightProvider.notifier).state = false;
    if (!ref.read(auth401CircuitOpenProvider)) {
      ref.read(authApiGateProvider.notifier).clearSuspend();
    }
  } catch (_) {}
}

/// Wait for resume JWT / 401 gate to clear before item-detail fetches (avoids false "load failed").
Future<void> awaitProviderApiReady(
  dynamic ref, {
  Duration maxWait = const Duration(seconds: 8),
}) async {
  if (!providerSkipApi(ref) && !providerAuthSoftPaused(ref)) return;
  final deadline = DateTime.now().add(maxWait);
  while (providerSkipApi(ref) || providerAuthSoftPaused(ref)) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}
