import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../models/session.dart';
import '../providers/api_degraded_provider.dart';
import '../providers/brokers_list_provider.dart';
import '../providers/business_aggregates_invalidation.dart'
    show invalidateWorkspaceSeedData;
import '../providers/catalog_providers.dart';
import '../providers/prefs_provider.dart';
import '../notifications/local_notifications_service.dart';
import '../providers/staff_home_providers.dart' show invalidateStaffHomeCaches;
import '../providers/suppliers_list_provider.dart';
import '../router/post_auth_route.dart' show sessionIsStaff;
import '../services/staff_activity_logger.dart';
import 'auth_failure_policy.dart';
import 'google_sign_in_helper.dart';
import 'secure_token_store.dart';
import 'session_cache.dart';

/// Bumps when session changes — wired to [GoRouter.refreshListenable].
final authRefresh = ValueNotifier<int>(0);

/// All parallel 401s share one refresh; avoids racing refresh/retries, double
/// refresh use, and provider storms that complete after Riverpod has disposed
/// [FutureProvider] elements (defunct + markNeedsBuild crashes on web).
Future<bool>? _unauthorizedRefreshInFlight;

Future<bool> _singleFlightUnauthorizedRefresh(
  bool Function() isDisposed,
  Future<bool> Function() refresh,
) {
  if (isDisposed()) return Future.value(false);
  if (_unauthorizedRefreshInFlight != null) {
    return _unauthorizedRefreshInFlight!;
  }
  _unauthorizedRefreshInFlight = () async {
    if (isDisposed()) return false;
    return refresh();
  }()
      .whenComplete(() {
    _unauthorizedRefreshInFlight = null;
  });
  return _unauthorizedRefreshInFlight!;
}

final hexaApiProvider = Provider<HexaApi>((ref) {
  // Riverpod 2.6 lacks `ref.mounted` — track disposal manually so async
  // callbacks don't read a dead ProviderContainer after widget/container
  // teardown (classic "ref after dispose" crash).
  var disposed = false;
  ref.onDispose(() => disposed = true);

  late final HexaApi api;
  api = HexaApi(
    // Pulls the access token from secure storage when an outgoing request is
    // missing an Authorization header. Covers the cold-start window between
    // app boot and [SessionNotifier.restore] finishing.
    resolveAccessToken: () async {
      if (disposed) return null;
      try {
        final store = ref.read(tokenStoreProvider);
        final t = await store.read();
        return t.access;
      } catch (_) {
        return null;
      }
    },
    onUnauthorizedRefresh: () => _singleFlightUnauthorizedRefresh(
          () => disposed,
          () async {
            if (disposed) return false;
            final store = ref.read(tokenStoreProvider);
            final t = await store.read();
            if (t.refresh == null) {
              // No refresh token means we cannot recover from 401s; clear the
              // session to prevent infinite request storms on web.
              try {
                if (!disposed) {
                  await ref.read(sessionProvider.notifier).logout();
                }
              } catch (_) {/* container disposed */}
              return false;
            }
            try {
              final pair = await api.refreshTokens(refreshToken: t.refresh!);
              if (disposed) return false;
              await store.write(access: pair.access, refresh: pair.refresh);
              api.setAuthToken(pair.access);
              if (disposed) return true;
              try {
                await ref
                    .read(sessionProvider.notifier)
                    .applyRefreshedTokens(pair.access, pair.refresh);
              } catch (_) {
                // SessionNotifier torn down — token is still persisted + attached.
              }
              return true;
            } on DioException catch (e) {
              final sc = e.response?.statusCode;
              final invalidRefresh = sc == 401 || sc == 403;
              if (!disposed && invalidRefresh) {
                try {
                  ref.read(authRefreshFailureTrackerProvider).reset();
                  ref.read(authSessionExpiredProvider.notifier).markExpired();
                  await ref.read(sessionProvider.notifier).logout();
                } catch (_) {/* container disposed */}
              } else if (!disposed) {
                final tracker = ref.read(authRefreshFailureTrackerProvider);
                tracker.recordTransientFailure();
                if (tracker.shouldForceLogout()) {
                  try {
                    tracker.reset();
                    ref.read(authSessionExpiredProvider.notifier).markExpired();
                    await ref.read(sessionProvider.notifier).logout();
                  } catch (_) {/* container disposed */}
                  return false;
                }
              }
              if (!disposed) {
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (disposed) return;
                  try {
                    ref.read(apiDegradedProvider.notifier).notifyDegraded(
                          invalidRefresh
                              ? 'Session expired — sign in again.'
                              : 'Connection issue while refreshing session. Retrying on next request.',
                        );
                    if (invalidRefresh) {
                      authRefresh.value++;
                    }
                  } catch (_) {}
                });
              }
              return false;
            } catch (_) {
              if (!disposed) {
                final tracker = ref.read(authRefreshFailureTrackerProvider);
                tracker.recordTransientFailure();
                if (tracker.shouldForceLogout()) {
                  try {
                    tracker.reset();
                    ref.read(authSessionExpiredProvider.notifier).markExpired();
                    await ref.read(sessionProvider.notifier).logout();
                  } catch (_) {/* container disposed */}
                  return false;
                }
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (disposed) return;
                  try {
                    ref.read(apiDegradedProvider.notifier).notifyDegraded(
                          'Temporary auth recovery issue. Session kept; retrying shortly.',
                        );
                  } catch (_) {}
                });
              }
              return false;
            }
          },
        ),
    onTerminalAuthFailure: (reason) async {
      if (disposed) return;
      try {
        ref.read(authRefreshFailureTrackerProvider).reset();
        ref.read(authSessionExpiredProvider.notifier).markExpired();
        await ref.read(sessionProvider.notifier).logout();
      } catch (_) {/* container disposed */}
    },
    authSessionExpired: () {
      if (disposed) return true;
      try {
        return ref.read(authSessionExpiredProvider);
      } catch (_) {
        return true;
      }
    },
    onConnectivityBanner: (degraded, hint) {
      if (disposed) return;
      // Dio interceptors can run synchronously while a frame is building; never
      // mutate Riverpod state mid-build (web: "setState/markNeedsBuild during build").
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (disposed) return;
        try {
          final n = ref.read(apiDegradedProvider.notifier);
          if (degraded) {
            if (hint != null && hint.isNotEmpty) {
              n.notifyDegraded(hint);
            } else {
              n.notifyDegraded();
            }
          } else {
            n.clear();
          }
        } catch (_) {
          /* ref/container disposed */
        }
      });
    },
  );
  return api;
});

final tokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore(ref.watch(sharedPreferencesProvider));
});

final sessionProvider =
    NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

/// Session for API providers: null when logged out or after terminal 401/refresh failure.
final activeSessionProvider = Provider<Session?>((ref) {
  if (ref.watch(authSessionExpiredProvider)) return null;
  return ref.watch(sessionProvider);
});

class SessionNotifier extends Notifier<Session?> {
  /// Tracked manually because Riverpod 2.6 does not expose `ref.mounted` on
  /// `NotifierProviderRef`. Flipped by [Ref.onDispose] in [build].
  bool _disposed = false;

  @override
  Session? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return null;
  }

  /// Serializes [restore], [login], [register], and [signInWithGoogle] so a concurrent
  /// [restore] (splash / login / cold start) cannot fire `logout()` from a dead refresh
  /// while new tokens are being written — which used to clear storage mid sign-up and
  /// leave the Create Account button spinning forever.
  Future<void> _authSerial = Future<void>.value();

  Future<T> _withAuthSerial<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _authSerial = _authSerial.then((_) async {
      try {
        if (!c.isCompleted) c.complete(await fn());
      } catch (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<void> applyRefreshedTokens(String access, String refresh) async {
    final cur = state;
    if (cur == null) return;
    state = Session(
      accessToken: access,
      refreshToken: refresh,
      businesses: cur.businesses,
      isSuperAdmin: cur.isSuperAdmin,
    );
  }

  Future<bool> _readIsSuperAdmin(HexaApi api) async {
    try {
      final p = await api.meProfile();
      return p['is_super_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistSession(Session session) async {
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    await cache.saveBusinesses(session.businesses,
        isSuperAdmin: session.isSuperAdmin);
  }

  void _clearAuthFailureFlags() {
    if (_disposed) return;
    try {
      ref.read(authSessionExpiredProvider.notifier).clear();
      ref.read(authRefreshFailureTrackerProvider).reset();
    } catch (_) {}
  }

  void _notifySessionExpiredBanner() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      try {
        ref.read(apiDegradedProvider.notifier).notifyDegraded(
              'Session expired — open Settings and sign in again.',
            );
      } catch (_) {}
    });
  }

  void _notifyOfflineCachedWorkspaceBanner() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      try {
        ref.read(apiDegradedProvider.notifier).notifyDegraded(
              'Offline — showing saved workspace. Reconnect to sync.',
            );
      } catch (_) {}
    });
  }

  /// Post-login bootstrap: does not block [restore] / [login] UI — runs after a microtask.
  /// Soft-fail: [HexaApi.bootstrapWorkspace] returns null on 404/501 (older server).
  void _scheduleWorkspaceBootstrap() {
    unawaited(_deferredWorkspaceBootstrap());
  }

  /// Fire-and-forget parallel fetches so party/catalog screens hit warm caches.
  void _warmWorkspaceListCaches() {
    Future<void>.microtask(() async {
      if (_disposed || state == null) return;
      try {
        await Future.wait<void>([
          ref.read(suppliersListProvider.future),
          ref.read(brokersListProvider.future),
          ref.read(itemCategoriesListProvider.future),
          ref.read(catalogItemsListProvider.future),
        ]);
      } catch (_) {/* soft-fail */}
    });
  }

  Future<void> _deferredWorkspaceBootstrap() async {
    await Future<void>.delayed(Duration.zero);
    if (_disposed) return;
    final session = state;
    if (session == null) return;
    final accessToken = session.accessToken;
    final api = ref.read(hexaApiProvider);
    try {
      final boot = await api.bootstrapWorkspace();
      if (_disposed) return;
      if (boot == null) return;
      if (boot['created_business'] == true) {
        final list = await api.meBusinesses();
        if (_disposed) return;
        if (state == null) return;
        if (state!.accessToken != accessToken) return;
        state = Session(
          accessToken: state!.accessToken,
          refreshToken: state!.refreshToken,
          businesses: list,
          isSuperAdmin: state!.isSuperAdmin,
        );
        await _persistSession(state!);
        if (_disposed) return;
        authRefresh.value++;
      }
      if (boot['seeded'] == true) {
        if (_disposed) return;
        invalidateWorkspaceSeedData(ref);
      }
    } on DioException catch (e) {
      assert(() {
        debugPrint('deferred workspace bootstrap: ${e.message}');
        return true;
      }());
    } catch (e) {
      assert(() {
        debugPrint('deferred workspace bootstrap: $e');
        return true;
      }());
    }
  }

  Future<void> restore() => _withAuthSerial(_restoreImpl);

  Future<void> _restoreImpl() async {
    final store = ref.read(tokenStoreProvider);
    final api = ref.read(hexaApiProvider);
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    ({String? access, String? refresh}) t;
    try {
      t = await store.read();
    } catch (_) {
      state = null;
      authRefresh.value++;
      return;
    }
    if (t.access == null || t.refresh == null) {
      state = null;
      authRefresh.value++;
      return;
    }
    api.setAuthToken(t.access);

    Future<void> finishOk(List<BusinessBrief> businesses) async {
      if (businesses.isEmpty) {
        state = null;
        await store.clear();
        await cache.clear();
        api.setAuthToken(null);
        authRefresh.value++;
        return;
      }
      final isSa = await _readIsSuperAdmin(api);
      final session = Session(
          accessToken: t.access!,
          refreshToken: t.refresh!,
          businesses: businesses,
          isSuperAdmin: isSa);
      state = session;
      await _persistSession(session);
      _clearAuthFailureFlags();
      authRefresh.value++;
      invalidateStaffHomeCaches(ref);
      _scheduleWorkspaceBootstrap();
      _warmWorkspaceListCaches();
    }

    try {
      final businesses = await api.meBusinesses();
      await finishOk(businesses);
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 401) {
        // Interceptor may have already cleared tokens via logout() after a failed refresh.
        final still = await store.read();
        if (still.access == null || still.refresh == null) {
          api.setAuthToken(null);
          state = null;
          authRefresh.value++;
          _notifySessionExpiredBanner();
          return;
        }
        try {
          final pair = await api.refreshTokens(refreshToken: still.refresh!);
          await store.write(access: pair.access, refresh: pair.refresh);
          api.setAuthToken(pair.access);
          final businesses = await api.meBusinesses();
          if (businesses.isEmpty) {
            await store.clear();
            await cache.clear();
            api.setAuthToken(null);
            state = null;
            authRefresh.value++;
            return;
          }
          final isSa = await _readIsSuperAdmin(api);
          final session = Session(
              accessToken: pair.access,
              refreshToken: pair.refresh,
              businesses: businesses,
              isSuperAdmin: isSa);
          state = session;
          await _persistSession(session);
          _clearAuthFailureFlags();
          authRefresh.value++;
          _scheduleWorkspaceBootstrap();
          _warmWorkspaceListCaches();
          return;
        } on DioException catch (re) {
          final rsc = re.response?.statusCode;
          // Once /me/businesses has already returned 401, any refresh failure
          // means this session cannot be trusted. Clear to prevent 401 loops.
          if (rsc == 401 || rsc == 403) {
            await store.clear();
            await cache.clear();
            api.setAuthToken(null);
            state = null;
            authRefresh.value++;
            _notifySessionExpiredBanner();
            return;
          }
          final cached = cache.loadBusinesses();
          if (cached != null && cached.isNotEmpty) {
            state = Session(
                accessToken: t.access!,
                refreshToken: t.refresh!,
                businesses: cached,
                isSuperAdmin: cache.loadIsSuperAdmin());
            authRefresh.value++;
            _notifyOfflineCachedWorkspaceBanner();
            return;
          }
          state = null;
          authRefresh.value++;
          return;
        } catch (_) {
          await store.clear();
          await cache.clear();
          api.setAuthToken(null);
          state = null;
          authRefresh.value++;
          _notifySessionExpiredBanner();
          return;
        }
      }
      if (_isRecoverableNetworkError(e)) {
        final cached = cache.loadBusinesses();
        if (cached != null && cached.isNotEmpty) {
          state = Session(
              accessToken: t.access!,
              refreshToken: t.refresh!,
              businesses: cached,
              isSuperAdmin: cache.loadIsSuperAdmin());
          authRefresh.value++;
          _notifyOfflineCachedWorkspaceBanner();
          return;
        }
        state = null;
        authRefresh.value++;
        return;
      }
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(
            accessToken: t.access!,
            refreshToken: t.refresh!,
            businesses: cached,
            isSuperAdmin: cache.loadIsSuperAdmin());
        authRefresh.value++;
        _notifyOfflineCachedWorkspaceBanner();
        return;
      }
      state = null;
      authRefresh.value++;
    } catch (_) {
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(
            accessToken: t.access!,
            refreshToken: t.refresh!,
            businesses: cached,
            isSuperAdmin: cache.loadIsSuperAdmin());
        authRefresh.value++;
        _notifyOfflineCachedWorkspaceBanner();
        return;
      }
      state = null;
      authRefresh.value++;
    }
  }

  bool _isRecoverableNetworkError(DioException e) {
    if (e.response != null) return false;
    final t = e.type;
    return t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout ||
        t == DioExceptionType.connectionError ||
        (t == DioExceptionType.unknown && e.response == null);
  }

  Future<void> login({required String email, required String password}) =>
      _withAuthSerial(
        () => _loginImpl(email: email, password: password),
      );

  void _notifyStaffAuthEvent(Session session, {required bool signedIn}) {
    if (!sessionIsStaff(session)) return;
    if (!ref.read(localNotificationsOptInProvider)) return;
    final biz = session.primaryBusiness.effectiveDisplayTitle;
    if (signedIn) {
      unawaited(LocalNotificationsService.instance
          .showStaffSignedIn(businessName: biz));
    } else {
      unawaited(LocalNotificationsService.instance
          .showStaffSignedOut(businessName: biz));
    }
  }

  Future<void> _loginImpl({
    required String email,
    required String password,
  }) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.login(email: email, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    final isSa = await _readIsSuperAdmin(api);
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses,
        isSuperAdmin: isSa);
    state = session;
    await _persistSession(session);
    _clearAuthFailureFlags();
    authRefresh.value++;
    invalidateStaffHomeCaches(ref);
    _notifyStaffAuthEvent(session, signedIn: true);
    if (sessionIsStaff(session)) {
      unawaited(StaffActivityLogger.logStaffLogin(ref));
    }
    _scheduleWorkspaceBootstrap();
    _warmWorkspaceListCaches();
  }

  Future<void> register(
      {required String username,
      required String email,
      required String password,
      String? name}) =>
      _withAuthSerial(
        () => _registerImpl(
          username: username,
          email: email,
          password: password,
          name: name,
        ),
      );

  Future<void> _registerImpl({
    required String username,
    required String email,
    required String password,
    String? name,
  }) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.register(
        username: username,
        email: email,
        password: password,
        name: name);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    final isSa = await _readIsSuperAdmin(api);
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses,
        isSuperAdmin: isSa);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
    invalidateStaffHomeCaches(ref);
    _scheduleWorkspaceBootstrap();
    _warmWorkspaceListCaches();
  }

  Future<void> signInWithGoogle({required String idToken}) =>
      _withAuthSerial(() => _signInWithGoogleImpl(idToken: idToken));

  Future<void> _signInWithGoogleImpl({required String idToken}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.loginWithGoogle(idToken: idToken);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    final isSa = await _readIsSuperAdmin(api);
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses,
        isSuperAdmin: isSa);
    state = session;
    await _persistSession(session);
    _clearAuthFailureFlags();
    authRefresh.value++;
    invalidateStaffHomeCaches(ref);
    _notifyStaffAuthEvent(session, signedIn: true);
    if (sessionIsStaff(session)) {
      unawaited(StaffActivityLogger.logStaffLogin(ref));
    }
    _scheduleWorkspaceBootstrap();
    _warmWorkspaceListCaches();
  }

  /// Reload workspaces from API (e.g. after branding update).
  Future<void> refreshBusinesses() async {
    final cur = state;
    if (cur == null) return;
    final api = ref.read(hexaApiProvider);
    final businesses = await api.meBusinesses();
    state = Session(
      accessToken: cur.accessToken,
      refreshToken: cur.refreshToken,
      businesses: businesses,
      isSuperAdmin: cur.isSuperAdmin,
    );
    await _persistSession(state!);
    authRefresh.value++;
  }

  Future<void> logout() async {
    final prev = state;
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    // Drop session + Bearer immediately so home/stock providers stop polling
    // while async Google sign-out and secure-store clears run (401 storms on web).
    state = null;
    api.setAuthToken(null);
    authRefresh.value++;
    if (prev != null) {
      _notifyStaffAuthEvent(prev, signedIn: false);
      if (sessionIsStaff(prev)) {
        unawaited(StaffActivityLogger.logStaffLogout(ref));
      }
    }
    await signOutGoogleIfNeeded();
    await store.clear();
    await cache.clear();
    try {
      ref.read(apiDegradedProvider.notifier).clear();
      ref.read(authSessionExpiredProvider.notifier).clear();
      ref.read(authRefreshFailureTrackerProvider).reset();
    } catch (_) {}
    invalidateStaffHomeCaches(ref);
  }
}
