import 'package:flutter/material.dart';

import '../errors/load_state_error.dart';
import 'friendly_load_error.dart';

/// Standard inline error card — use instead of raw exception text in UI.
class HexaErrorCard extends StatelessWidget {
  const HexaErrorCard({
    super.key,
    this.message = 'Could not load data',
    this.subtitle = kFriendlyLoadNetworkSubtitle,
    required this.onRetry,
  });

  /// Maps [error] to safe copy; never shows Dio/stack text.
  factory HexaErrorCard.fromError({
    required Object error,
    required VoidCallback onRetry,
    String title = 'Could not load data',
  }) {
    return HexaErrorCard(
      message: title,
      subtitle: loadStateErrorSubtitle(error),
      onRetry: onRetry,
    );
  }

  final String message;
  final String? subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FriendlyLoadError(
      message: message,
      subtitle: subtitle,
      onRetry: onRetry,
    );
  }
}

/// Compact row for embedded forms (dropdown loaders, etc.).
class InlineLoadError extends StatelessWidget {
  const InlineLoadError({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.error,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          loadStateErrorSubtitle(error),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
