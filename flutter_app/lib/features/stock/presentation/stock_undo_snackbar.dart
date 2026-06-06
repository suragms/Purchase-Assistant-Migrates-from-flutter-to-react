import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/stock_providers.dart';

/// One-shot undo after a quick stock patch (server validates 15 min / same user).
void showStockUndoSnackBar({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Stock updated — $itemName'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final session = ref.read(sessionProvider);
          if (session == null) return;
          try {
            await ref.read(hexaApiProvider).undoLastStockChange(
                  businessId: session.primaryBusiness.id,
                  itemId: itemId,
                );
            invalidateWarehouseSurfaces(ref);
            ref.invalidate(stockListProvider);
            if (context.mounted) {
              final m = ScaffoldMessenger.maybeOf(context);
              m?.showSnackBar(
                const SnackBar(content: Text('Change undone')),
              );
            }
          } catch (_) {
            if (context.mounted) {
              final m = ScaffoldMessenger.maybeOf(context);
              m?.showSnackBar(
                const SnackBar(
                  content: Text('Could not undo — change may be too old'),
                ),
              );
            }
          }
        },
      ),
      duration: const Duration(seconds: 12),
    ),
  );
}
