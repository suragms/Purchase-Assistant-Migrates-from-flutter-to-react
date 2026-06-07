import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/hexa_colors.dart';
import '../../features/shell/shell_branch_provider.dart';

/// Lightweight shell tab wrapper.
///
/// Previously hijacked [FlutterError.onError] and turned unrelated widget faults
/// into full-tab "Home could not load" screens. Section failures now use
/// [ErrorWidget.builder] (`buildHexaLayoutErrorWidget`); API failures use
/// [FriendlyLoadError] inside each page.
class HexaPageErrorBoundary extends ConsumerWidget {
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

  /// When set, off-tab shells return [child] only (IndexedStack keeps pages mounted).
  final int? shellBranchIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = shellBranchIndex;
    if (idx != null && ref.watch(shellCurrentBranchProvider) != idx) {
      return child;
    }
    return ColoredBox(
      color: HexaColors.brandBackground,
      child: SizedBox.expand(child: child),
    );
  }
}

/// Shared heuristics for layout/network/transient failures (legacy callers).
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
      s.contains('Box not found') ||
      s.contains('modifying a provider') ||
      s.contains('Tried to modify a provider') ||
      s.contains('Cannot use "ref"') ||
      s.contains('childAspectRatio') ||
      s.contains('AssertionError') ||
      s.contains('is not a subtype of') ||
      s.contains('mA<void>') ||
      s.contains('minified:mA');
}
