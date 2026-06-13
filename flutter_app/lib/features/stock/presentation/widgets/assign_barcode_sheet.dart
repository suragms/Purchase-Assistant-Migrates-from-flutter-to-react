import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/auth/session_permissions.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/design_system/hexa_responsive.dart';

Future<bool> showAssignBarcodeSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  String? suggestedBarcode,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;
  if (sessionIsStockReadOnly(session)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Read-only account — cannot assign barcodes. Ask owner/manager.',
        ),
      ),
    );
    return false;
  }
  final ctrl = TextEditingController(text: suggestedBarcode ?? '');
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
              'Assign barcode',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: saving
                  ? null
                  : () {
                      Navigator.pop(context);
                      context.push('/barcode/scan');
                    },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan packaging barcode'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Barcode *'),
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final code = ctrl.text.trim();
                      if (code.isEmpty) return;
                      final session = ref.read(sessionProvider);
                      if (session == null) return;
                      setSheetState(() => saving = true);
                      try {
                        final lookup =
                            await ref.read(hexaApiProvider).barcodeStockLookup(
                                  businessId: session.primaryBusiness.id,
                                  code: code,
                                );
                        final otherId = lookup['item_id']?.toString() ??
                            lookup['catalog_item_id']?.toString() ??
                            '';
                        if (otherId.isNotEmpty && otherId != itemId) {
                          final otherName =
                              lookup['name']?.toString() ?? 'another item';
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Barcode $code is already assigned to $otherName. Use a different barcode.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        await ref.read(hexaApiProvider).patchCatalogItemBarcode(
                              businessId: session.primaryBusiness.id,
                              itemId: itemId,
                              barcode: code,
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
