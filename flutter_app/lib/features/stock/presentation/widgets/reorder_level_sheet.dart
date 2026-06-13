import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/design_system/hexa_responsive.dart';

/// Inline reorder-level editor shared by item detail and staff low-stock flows.
Future<bool> showReorderLevelSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  required String unit,
  double currentReorder = 0,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;

  final ctrl = TextEditingController(
    text: currentReorder > 0 ? currentReorder.toString() : '',
  );
  var saving = false;
  final saved = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set reorder level — $itemName',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'When stock falls below this number, low-stock alerts trigger.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              enabled: !saving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Reorder at',
                hintText: 'e.g. 10',
                suffixText: unit.toUpperCase(),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final text = ctrl.text.trim();
                      final v = double.tryParse(text);
                      if (v == null || v < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid number')),
                        );
                        return;
                      }
                      setSheetState(() => saving = true);
                      try {
                        await ref.read(hexaApiProvider).updateCatalogItem(
                              businessId: session.primaryBusiness.id,
                              itemId: itemId,
                              patchReorderLevel: true,
                              reorderLevel: v,
                            );
                        ref.invalidate(catalogItemDetailProvider(itemId));
                        ref.invalidate(stockItemDetailProvider(itemId));
                        invalidateCatalogItemSaveSurfaces(ref, itemId: itemId);
                        invalidateStockRowSaveSurfaces(
                          ref,
                          itemId: itemId,
                          reorderAlert: true,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      } on DioException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyApiError(e))),
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
  if (saved != true || !context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Reorder level updated')),
  );
  return true;
}

/// Reads reorder level from a stock list row map.
double reorderLevelFromStockRow(Map<String, dynamic> item) =>
    coerceToDouble(item['reorder_level']);
