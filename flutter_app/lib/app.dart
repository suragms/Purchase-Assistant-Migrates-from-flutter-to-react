import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'core/notifications/post_login_notification_prompt.dart';
import 'core/providers/reports_provider.dart';
import 'core/providers/analytics_kpi_provider.dart';
import 'features/reports/reports_prefs.dart';
import 'core/reporting/trade_report_aggregate.dart';
import 'core/notifications/local_notifications_service.dart';
import 'core/platform/launcher_quick_actions.dart';
import 'core/platform/remove_boot_overlay.dart';
import 'core/providers/api_degraded_provider.dart';
import 'core/providers/home_breakdown_tab_providers.dart';
import 'core/providers/home_dashboard_provider.dart';
import 'core/auth/session_notifier.dart';
import 'core/config/app_config.dart';
import 'core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches, tradePurchasesListProvider;
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/hexa_colors.dart';
import 'core/widgets/hexa_page_error_boundary.dart';

String _n0(double v) =>
    (v - v.roundToDouble()).abs() < 1e-6 ? '${v.round()}' : v.toStringAsFixed(1);

String _qtyLine(TradeReportTotals t) {
  final p = <String>[];
  if (t.kg > 1e-9) p.add('${_n0(t.kg)} KG');
  if (t.bags > 1e-9) p.add('${_n0(t.bags)} BAGS');
  if (t.boxes > 1e-9) p.add('${_n0(t.boxes)} BOX');
  if (t.tins > 1e-9) p.add('${_n0(t.tins)} TIN');
  return p.join(' • ');
}

class _NotificationTapHandler extends ConsumerStatefulWidget {
  const _NotificationTapHandler({required this.child});
  final Widget child;

  @override
  ConsumerState<_NotificationTapHandler> createState() =>
      _NotificationTapHandlerState();
}

class _NotificationTapHandlerState extends ConsumerState<_NotificationTapHandler> {
  StreamSubscription<String>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = LocalNotificationsService.instance.payloadStream.listen((payload) {
      if (payload.trim() == 'whatsapp_report') {
        _onWhatsAppReportTapped();
      }
    });
  }

  Future<void> _onWhatsAppReportTapped() async {
    if (_busy) return;
    _busy = true;
    try {
      final enabled = await ReportsPrefs.getScheduleEnabled();
      final phone = await ReportsPrefs.getSchedulePhone();
      final type = await ReportsPrefs.getScheduleType();
      if (!enabled || phone.trim().isEmpty) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = switch (type) {
        'daily' => (today, today),
        'monthly' => (today.subtract(const Duration(days: 29)), today),
        _ => (today.subtract(const Duration(days: 6)), today),
      };

      ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
      // WidgetRef is distinct from riverpod's Ref; implementation supports .read.
      final payload = await fetchReportsPurchasesLiveForAnalytics(ref as Ref);
      ref.invalidate(reportsPurchasesPayloadProvider);
      final purchases = payload.items;
      final agg = buildTradeReportAgg(purchases);

      final df = DateFormat('d MMM');
      final t = agg.totals;
      final parts = <String>[
        'Purchase Report (${df.format(from)} → ${df.format(to)})',
        '',
        'Total: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(t.inr)}',
        _qtyLine(t),
      ]..removeWhere((e) => e.trim().isEmpty);

      final msg = Uri.encodeComponent(parts.join('\n'));
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final uri = Uri.parse('https://wa.me/$digits?text=$msg');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ignore: best-effort convenience entrypoint.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _HexaScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

/// Binds launcher shortcuts to [appRouterProvider] on first frame so cold starts
/// from a home-screen action work before [ShellScreen] exists.
class _LauncherShortcutsBootstrap extends ConsumerStatefulWidget {
  const _LauncherShortcutsBootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_LauncherShortcutsBootstrap> createState() =>
      _LauncherShortcutsBootstrapState();
}

class _LauncherShortcutsBootstrapState
    extends ConsumerState<_LauncherShortcutsBootstrap> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bindLauncherShortcutsRouter(ref.read(appRouterProvider));
      unawaited(setupLauncherQuickActions());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Heuristic: transient layout / lifecycle issues should not replace the entire app.
bool _hexaFlutterErrorLikelyNonFatal(FlutterErrorDetails details) =>
    hexaErrorLikelyNonFatal(details);

/// Catches framework errors so the web build can show recovery UI instead of a blank screen.
class _HexaErrorBoundary extends StatefulWidget {
  const _HexaErrorBoundary({
    required this.child,
    required this.onGoHome,
  });

  final Widget child;
  final VoidCallback onGoHome;

  @override
  State<_HexaErrorBoundary> createState() => _HexaErrorBoundaryState();
}

class _HexaErrorBoundaryState extends State<_HexaErrorBoundary> {
  Object? _error;
  void Function(FlutterErrorDetails)? _previousOnError;

  @override
  void initState() {
    super.initState();
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _previousOnError?.call(details);
      if (!mounted) return;
      if (_hexaFlutterErrorLikelyNonFatal(details)) {
        FlutterError.dumpErrorToConsole(details);
        return;
      }
      // Never call setState from inside another widget's build / focus callbacks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _error = details.exception);
      });
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _previousOnError;
    super.dispose();
  }

  void _clearError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _error = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Material(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Could not load the app. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (kDebugMode && _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error.toString().split('\n').first,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _clearError,
                      child: const Text('Retry'),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        _clearError();
                        widget.onGoHome();
                      },
                      child: const Text('Go to Home'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}

class HexaApp extends ConsumerWidget {
  const HexaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final session = ref.watch(sessionProvider);
    final title = session?.primaryBusiness.effectiveDisplayTitle ??
        AppConfig.appName;
    // Harisree: light iOS-style surfaces only (gray / white / teal) — no dark mode in product UI.
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: title,
      theme: buildHexaTheme(Brightness.light),
      darkTheme: buildHexaTheme(Brightness.light),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        removeBootOverlayIfPresent();
        // Web: the router [child] can lay out with zero intrinsic height unless we
        // force it to fill the viewport — otherwise the shell / Home body stays blank
        // while the bottom bar (sibling scaffold) still paints.
        final body = SizedBox.expand(
          child: child ?? const SizedBox.shrink(),
        );
        final banner = ref.watch(apiDegradedProvider);
        // Stack (not Column+Expanded): [MaterialApp.router] builder can get unbounded
        // height on web; Expanded would overflow. Overlay for tooltips lives under
        // [Navigator]/[child]; keep dismiss control without Tooltip (no Overlay ancestor).
        final shell = banner != null && banner.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: body),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Material(
                      elevation: 0,
                      color: const Color(0xFFE8F4F2),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_queue_rounded,
                                size: 20,
                                color: HexaColors.brandPrimary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  banner,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: const Color(0xFF1C1917),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        height: 1.25,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!context.mounted) return;
                                    ref.invalidate(homeDashboardDataProvider);
                                    ref.invalidate(homeShellReportsProvider);
                                    invalidateTradePurchaseCaches(ref);
                                    ref.invalidate(tradePurchasesListProvider);
                                    ref.invalidate(reportsPurchasesPayloadProvider);
                                  });
                                },
                                child: const Text('Retry'),
                              ),
                              Semantics(
                                label: 'Dismiss connection notice',
                                button: true,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  // No [tooltip]: this subtree is a sibling of the router
                                  // [Navigator] in the builder Stack — tooltips need an Overlay.
                                  icon: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!context.mounted) return;
                                      ref
                                          .read(apiDegradedProvider.notifier)
                                          .clear();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : body;
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.appShellGradient),
            child: _HexaErrorBoundary(
              onGoHome: () => ref.read(appRouterProvider).go('/home'),
              child: _LauncherShortcutsBootstrap(
                child: _NotificationTapHandler(
                  child: PostLoginNotificationPrompt(child: shell),
                ),
              ),
            ),
          ),
        );
      },
      scrollBehavior: _HexaScrollBehavior(),
    );
  }
}
