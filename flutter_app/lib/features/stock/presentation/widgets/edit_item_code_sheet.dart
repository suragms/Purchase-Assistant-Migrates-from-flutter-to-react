import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/utils/item_code_format.dart';
import '../../../../core/design_system/hexa_responsive.dart';

Future<bool> showEditItemCodeSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  String? currentCode,
}) async {
  final ctrl = TextEditingController(text: currentCode ?? '');
  var saving = false;
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit item code',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Item code *',
                hintText: 'RICE-PONNI-50KG',
              ),
              inputFormatters: [ItemCodeInputFormatter()],
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final code = normalizeItemCode(ctrl.text);
                      if (!isValidItemCode(code)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Use A-Z, 0-9, hyphen, underscore only',
                            ),
                          ),
                        );
                        return;
                      }
                      final session = ref.read(sessionProvider);
                      if (session == null) return;
                      setSheetState(() => saving = true);
                      try {
                        await ref.read(hexaApiProvider).patchCatalogItemCode(
                              businessId: session.primaryBusiness.id,
                              itemId: itemId,
                              itemCode: code,
                            );
                        invalidateCatalogItemSaveSurfaces(ref, itemId: itemId);
                        invalidateStockRowSaveSurfaces(
                          ref,
                          itemId: itemId,
                          immediateListReconcile: true,
                        );
                        ref.invalidate(catalogItemDetailProvider(itemId));
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(userFacingError(e))),
                          );
                        }
                      } finally {
                        if (context.mounted) {
                          setSheetState(() => saving = false);
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return result == true;
}
