import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/providers/trade_purchases_provider.dart';
import '../../../../core/design_system/hexa_responsive.dart';

Future<bool> showAssignBarcodeSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  String? suggestedBarcode,
}) async {
  final ctrl = TextEditingController(text: suggestedBarcode ?? '');
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => HexaResponsiveSheetViewport(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign barcode',
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Barcode *'),
            keyboardType: TextInputType.text,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              final session = ref.read(sessionProvider);
              if (session == null) return;
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
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
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
                invalidateWarehouseSurfaces(ref);
                ref.invalidate(stockListProvider);
                ref.invalidate(bulkStockListProvider);
                ref.invalidate(catalogItemsListProvider);
                invalidateTradePurchaseCaches(ref);
                ref.invalidate(catalogItemDetailProvider(itemId));
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result == true;
}
