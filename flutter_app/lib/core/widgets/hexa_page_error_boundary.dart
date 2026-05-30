import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/hexa_colors.dart';
import '../../features/shell/shell_branch_provider.dart';

/// Page-scoped error boundary — keeps one screen's failure from replacing the
/// entire app shell (notably Reports on cold web load).
///
/// When [shellBranchIndex] is set, only the **visible** IndexedStack tab
/// registers [FlutterError.onError]. Otherwise an off-screen Home crash could
/// surface as "Reports could not load" because lazy branches had not mounted yet.
class HexaPageErrorBoundary extends ConsumerStatefulWidget {
  const HexaPageErrorBoundary({
    super.key,
    required this.child,
    required this.title,
    this.subtitle,
    this.fallbackRoute = '/home',
    this.onRetry,
    this.shellBranchIndex,
  });

  final Widget child;
  final String title;
  final String? subtitle;
  final String fallbackRoute;
  final VoidCallback? onRetry;
  /// [ShellBranch] index for this tab — limits error capture to the active tab.
  final int? shellBranchIndex;

  @override
  ConsumerState<HexaPageErrorBoundary> createState() =>
      _HexaPageErrorBoundaryState();
}

class _HexaPageErrorBoundaryState extends ConsumerState<HexaPageErrorBoundary> {
  Object? _error;
  void Function(FlutterErrorDetails)? _previousOnError;
  static _HexaPageErrorBoundaryState? _registered;

  bool get _shouldHandleErrors {
    final idx = widget.shellBranchIndex;
    if (idx == null) return true;
    return ref.read(shellCurrentBranchProvider) == idx;
  }

  void _installHandler() {
    if (_registered == this) return;
    _registered?._uninstallHandler();
    _previousOnError = FlutterError.onError;
    FlutterError.onError = _onFlutterError;
    _registered = this;
  }

  void _uninstallHandler() {
    if (_registered != this) return;
    FlutterError.onError = _previousOnError;
    _previousOnError = null;
    _registered = null;
  }

  void _syncErrorHandler() {
    if (!mounted) return;
    if (_shouldHandleErrors) {
      _installHandler();
    } else {
      _uninstallHandler();
    }
  }

  void _onFlutterError(FlutterErrorDetails details) {
    if (!_shouldHandleErrors) {
      _previousOnError?.call(details);
      return;
    }
    if (hexaErrorLikelyNonFatal(details)) {
      _previousOnError?.call(details);
      return;
    }
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shouldHandleErrors) return;
      setState(() => _error = details.exception);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncErrorHandler());
  }

  @override
  void dispose() {
    _uninstallHandler();
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
    ref.listen<int>(shellCurrentBranchProvider, (_, __) {
      _syncErrorHandler();
      if (!_shouldHandleErrors && _error != null) {
        _clearError();
      }
    });

    if (_error != null && _shouldHandleErrors) {
      final detail = _error.toString().split('\n').first;
      return Material(
        color: HexaColors.brandBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 44, color: Colors.orange),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle ??
                      'Something went wrong loading this screen. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: HexaColors.textBody,
                    height: 1.35,
                  ),
                ),
                if (kDebugMode && detail.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {
                        _clearError();
                        widget.onRetry?.call();
                      },
                      child: const Text('Retry'),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        _clearError();
                        if (context.mounted) context.go(widget.fallbackRoute);
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

/// Shared heuristics for layout/network/transient failures.
bool hexaErrorLikelyNonFatal(FlutterErrorDetails details) {
  if (details.silent) return true;
  final s = details.exceptionAsString();
  return s.contains('RenderFlex') ||
      s.contains('overflowed') ||
      s.contains('BoxConstraints') ||
      s.contains('viewport') ||
      s.contains('RenderViewport') ||
      s.contains('ParentDataWidget') ||
      s.contains('Incorrect use of ParentDataWidget') ||
      s.contains('Cannot hit test a render box that has never been laid out') ||
      s.contains('Looking up a deactivated widget') ||
      s.contains('setState() or markNeedsBuild() called during build') ||
      s.contains('wrong build scope') ||
      s.contains('Cannot get renderObject of inactive element') ||
      s.contains('inactive element') ||
      s.contains('setState() called after dispose()') ||
      s.contains('UnmountedRefException') ||
      s.contains('Bad state: Cannot use') ||
      s.contains('TickerFuture') ||
      s.contains('AnimationController.dispose() called more than once') ||
      s.contains('DioException') ||
      s.contains('SocketException') ||
      s.contains('TimeoutException') ||
      s.contains('FormatException') ||
      s.contains('NoSuchMethodError') ||
      s.contains('PlatformException') ||
      s.contains('StaleHomeDashboardFetch') ||
      s.contains('ProviderException') ||
      s.contains('StateError') ||
      s.contains('GoError') ||
      s.contains('nothing to pop') ||
      s.contains('There is nothing to pop') ||
      s.contains('RenderBox was not laid out') ||
      s.contains('Vertical viewport was given unbounded height') ||
      s.contains('HiveError') ||
      s.contains('Box not found');
}
