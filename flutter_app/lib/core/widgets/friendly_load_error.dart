import 'package:flutter/material.dart';

/// Default [FriendlyLoadError.subtitle] for typical network / connectivity failures.
const String kFriendlyLoadNetworkSubtitle =
    'Check your connection and try again.';

/// Inline error state with retry — avoids exposing raw exception strings to users.
class FriendlyLoadError extends StatelessWidget {
  const FriendlyLoadError({
    super.key,
    required this.onRetry,
    this.message = 'Unable to load data',
    this.subtitle = kFriendlyLoadNetworkSubtitle,
    this.offline = false,
    this.onShowCached,
  });

  final VoidCallback onRetry;
  final String message;

  /// Shown under [message]. Defaults to [kFriendlyLoadNetworkSubtitle]; pass `null` to hide.
  final String? subtitle;

  /// When true, uses offline icon and copy unless [subtitle] overrides.
  final bool offline;

  /// Optional action to open last cached snapshot (warehouse surfaces).
  final VoidCallback? onShowCached;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        offline
                            ? Icons.wifi_off_rounded
                            : Icons.cloud_off_rounded,
                        size: 32,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Retry'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (onShowCached != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onShowCached,
                      child: const Text('Show cached data'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
