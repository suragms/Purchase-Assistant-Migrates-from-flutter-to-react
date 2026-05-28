import 'package:flutter/material.dart';

/// Compact inline error tile for dense list/card sections.
class SectionInlineError extends StatelessWidget {
  const SectionInlineError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minVerticalPadding: 0,
      leading: const Icon(Icons.warning_amber_rounded, size: 18),
      title: Text(
        message,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      trailing: TextButton(
        onPressed: onRetry,
        child: const Text('Retry'),
      ),
    );
  }
}
