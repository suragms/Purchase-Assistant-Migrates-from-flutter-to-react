import 'package:flutter/material.dart';

/// Shows a snackbar that floats near the **top** of the screen so it does not cover
/// bottom CTAs, nav bars, or wizard footers.
void showTopSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final mq = MediaQuery.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_rounded : Icons.check_circle_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFB91C1C) : const Color(0xFF0D6B5E),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: (mq.size.height - mq.padding.top - 72).clamp(8.0, mq.size.height),
      ),
      duration: duration,
      action: action,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
