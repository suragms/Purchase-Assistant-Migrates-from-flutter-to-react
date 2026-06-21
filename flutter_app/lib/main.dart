import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/api/api_warmup.dart';
import 'core/auth/provider_api_guard.dart'
    show ProviderFetchAborted, registerRootProviderContainer;
import 'core/providers/stock_list_exceptions.dart'
    show StockListFetchBlockedException;
import 'core/auth/session_notifier.dart' show sessionProvider, hexaApiProvider;
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/platform/hexa_layout_error_widget.dart';
import 'core/widgets/hexa_page_error_boundary.dart'
    show hexaAsyncErrorLikelyBenign, hexaErrorLikelyNonFatal;
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/prefs_provider.dart'
    show kNotificationsOptInKey, sharedPreferencesProvider;
import 'core/providers/api_degraded_provider.dart';
import 'core/services/offline_store.dart';
import 'core/services/offline_sync_service.dart';
import 'core/services/pdf_locale.dart';

class _AppProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    if (error is ProviderFetchAborted) return;
    if (error is StockListFetchBlockedException) return;
    if (error is StateError &&
        (error.message.contains('onDispose') ||
            error.message.contains('disposed'))) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[Provider Error] ${provider.name ?? provider.runtimeType}: $error',
      );
    }
  }
}

void _installHexaPlatformAsyncErrorHook() {
  final prev = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (prev != null && prev(error, stack)) {
      return true;
    }
    if (kDebugMode) {
      debugPrint('[Hexa] PlatformDispatcher.onError: $error\n$stack');
    }
    if (hexaAsyncErrorLikelyBenign(error)) {
      return true;
    }
    return false;
  };
}

/// Pre-[HexaApp] UI must not use [MaterialApp]: on web the engine sets
/// [PlatformDispatcher.defaultRouteName] to the browser path (e.g. `/home`).
/// [MaterialApp] wires an internal [Navigator] that may run
/// [Navigator.defaultGenerateInitialRoutes] against an empty route table →
/// "Could not navigate to initial route" and a broken stack / blank home after
/// [MaterialApp.router] mounts.
Widget _bootstrapChrome(Widget child) {
  final ui.FlutterView? view = ui.PlatformDispatcher.instance.implicitView ??
      (ui.PlatformDispatcher.instance.views.isNotEmpty
          ? ui.PlatformDispatcher.instance.views.first
          : null);
  final MediaQueryData mq =
      view != null ? MediaQueryData.fromView(view) : const MediaQueryData();

  return MediaQuery(
    data: mq,
    child: Theme(
      data: buildHexaTheme(Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          type: MaterialType.canvas,
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Blocks the app on wrong Vercel hostname — CORS rejects all API calls from JS.
class _WrongWebHostGate extends StatelessWidget {
  const _WrongWebHostGate();

  @override
  Widget build(BuildContext context) {
    final target = AppConfig.wrongHostRedirectUrl();
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link_off_rounded,
                    size: 56,
                    color: HexaColors.brandPrimary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Wrong app link',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: HexaColors.brandPrimary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You opened ${Uri.base.host}. Suppliers, stock saves, and '
                    'purchases fail here because the server only accepts '
                    '${Uri.parse(AppConfig.productionWebUrl).host}.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      final uri = Uri.parse(target);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, webOnlyWindowName: '_self');
                      }
                    },
                    child: const Text('Open Harisree Warehouse'),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    target,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HexaColors.brandPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = buildHexaLayoutErrorWidget;
  _installHexaPlatformAsyncErrorHook();
  FlutterError.onError = (FlutterErrorDetails details) {
    if (hexaErrorLikelyNonFatal(details) ||
        hexaAsyncErrorLikelyBenign(details.exception)) {
      if (kDebugMode) {
        debugPrint('[Hexa] FlutterError (suppressed): ${details.exception}');
      }
      return;
    }
    FlutterError.presentError(details);
  };
  // Clean URLs on web (e.g. /home instead of #/home). Requires SPA rewrites (see repo vercel.json).
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  // Cursor IDE / Playwright snapshots read the web a11y tree. Flutter web
  // otherwise defers full semantics until a screen reader opts in (the
  // "Enable accessibility" overlay), so snapshots look empty even when the
  // canvas UI is fine. Debug + profile only — release keeps default behavior.
  if (kIsWeb && !kReleaseMode) {
    WidgetsBinding.instance.ensureSemantics();
  }
  // Do not await Hive / prefs / restore here: on web, flutter_bootstrap.js awaits
  // runApp until this async main() completes — a long wait leaves the HTML "Starting…"
  // overlay up and looks like a frozen white screen.
  runApp(const _HexaBootstrap());
}

class _HexaBootstrap extends StatefulWidget {
  const _HexaBootstrap();

  @override
  State<_HexaBootstrap> createState() => _HexaBootstrapState();
}

class _HexaBootstrapState extends State<_HexaBootstrap> {
  ProviderContainer? _container;
  Object? _error;
  String? _errorStackTrace;
  String _splashStatus = 'Connecting to server…';
  Timer? _splashSlowTimer;

  @override
  void dispose() {
    _splashSlowTimer?.cancel();
    super.dispose();
  }

  void _bootstrapLog(String message) {
    if (kDebugMode) {
      debugPrint('[bootstrap] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _splashSlowTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _container != null) return;
      setState(() {
        _splashStatus = 'Server waking up, please wait…';
      });
    });
    unawaited(_prepare());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removeBootOverlayIfPresent();
    });
  }

  Future<void> _prepare() async {
    setState(() {
      _error = null;
      _errorStackTrace = null;
    });

    final cap = kIsWeb ? const Duration(seconds: 15) : const Duration(minutes: 2);

    try {
      await OfflineStore.init().timeout(cap);
      _bootstrapLog('OfflineStore.init OK');
      final prefs = await SharedPreferences.getInstance().timeout(cap);
      _bootstrapLog('SharedPreferences OK');
      await LocalNotificationsService.instance.init();
      final notifOptIn = prefs.getBool(kNotificationsOptInKey) ?? false;
      await LocalNotificationsService.instance.setOptIn(notifOptIn);

      if (!kIsWeb) {
        await LocalNotificationsService.instance
            .scheduleHarisreeReminders(enabled: notifOptIn);
      }

      final container = ProviderContainer(
        observers: [_AppProviderObserver()],
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      registerRootProviderContainer(container);
      _bootstrapLog('ProviderContainer OK');

      try {
        await container.read(sessionProvider.notifier).restore().timeout(
              kIsWeb ? const Duration(seconds: 20) : const Duration(seconds: 25),
            );
        _bootstrapLog('session.restore OK');
      } catch (_) {
        // Offline / timeout — splash/login handle retry.
        _bootstrapLog('session.restore skipped or failed (non-fatal)');
      }

      // Health warm-up runs below (non-blocking) so HexaApp mounts immediately on web
      // release — blocking here left a blank gray page after the HTML splash timed out.

      unawaited(() async {
        try {
          final api = container.read(hexaApiProvider);
          var healthUnreachable = false;
          await ApiWarmupService.pingHealth(
            api,
            onSlow: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                container.read(apiDegradedProvider.notifier).notifyDegraded(
                      'Waking server (~30s) — first load may take a moment',
                    );
              });
            },
            onUnreachable: () {
              healthUnreachable = true;
            },
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (healthUnreachable) {
              final base = AppConfig.resolvedApiBaseUrl;
              final hint = AppConfig.apiBasePointsToLoopback
                  ? 'Cannot reach $base — start the FastAPI server (e.g. uvicorn on port 8000), or run with --dart-define=API_BASE_URL=…'
                  : 'Cannot reach $base — check that the API is up and that Vercel/build defines API_BASE_URL correctly.';
              container.read(apiDegradedProvider.notifier).notifyDegraded(hint);
              return;
            }
            container.read(apiDegradedProvider.notifier).clear();
          });
          ApiWarmupService.startPeriodicHealth(api);
          try {
            await api.healthReady().timeout(const Duration(seconds: 8));
          } on DioException catch (e) {
            if (e.response?.statusCode == 503) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                container.read(apiDegradedProvider.notifier).notifyDegraded(
                      'Waking server (~30s) — database still starting',
                    );
              });
            }
          }
        } catch (_) {}
      }());

      // Offline queue sync (best-effort): pushes queued writes when connectivity returns.
      OfflineSyncService.start(container);

      if (!mounted) return;
      _splashSlowTimer?.cancel();
      _bootstrapLog('starting HexaApp');
      setState(() => _container = container);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        removeBootOverlayIfPresent(force: true);
      });
      // Defer PDF locale setup: avoids blocking cold start path.
      unawaited(() async {
        try {
          await ensurePdfLocalesInitialized().timeout(const Duration(seconds: 8));
          _bootstrapLog('pdf locales OK (deferred)');
        } catch (_) {}
      }());
    } catch (e, st) {
      debugPrint('Bootstrap failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorStackTrace = kDebugMode ? st.toString() : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && AppConfig.isWrongProductionWebHost) {
      return _bootstrapChrome(const _WrongWebHostGate());
    }
    if (_error != null) {
      return _bootstrapChrome(
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) => Text(
                          kIsWeb
                              ? 'Could not start offline storage. Try a hard refresh or another browser.'
                              : 'Could not start the app.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (kDebugMode && _error != null) ...[
                        Builder(
                          builder: (context) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Debug detail',
                                    style: Theme.of(context).textTheme.labelLarge,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  _error.toString(),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontFamily: 'monospace',
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                if (_errorStackTrace != null) ...[
                                  const SizedBox(height: 12),
                                  SelectableText(
                                    _errorStackTrace!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          return Material(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              onTap: () => unawaited(_prepare()),
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                child: Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_container == null) {
      return _bootstrapChrome(
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Harisree',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: HexaColors.brandPrimary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _splashStatus,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return UncontrolledProviderScope(
      container: _container!,
      child: const HexaApp(),
    );
  }
}
