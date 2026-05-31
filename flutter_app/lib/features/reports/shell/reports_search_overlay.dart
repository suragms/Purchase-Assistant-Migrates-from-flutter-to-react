import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';

/// Expandable search overlay (not a permanent scroll field).
Future<String?> showReportsSearchOverlay({
  required BuildContext context,
  required String hint,
  String initialQuery = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HexaColors.brandBackground,
    builder: (ctx) {
      final ctl = TextEditingController(text: initialQuery);
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () => ctl.clear(),
                ),
                filled: true,
                fillColor: HexaColors.brandCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: HexaColors.brandBorder),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Search'),
            ),
          ],
        ),
      );
    },
  );
}
