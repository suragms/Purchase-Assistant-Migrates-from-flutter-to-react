import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/business_aggregates_invalidation.dart';
import '../../core/providers/business_write_event.dart';

/// Shell-level fan-out: any purchase/stock write refreshes warehouse providers app-wide.
class BusinessWriteStockListener extends ConsumerWidget {
  const BusinessWriteStockListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<BusinessWriteEvent>(businessWriteEventProvider, (prev, next) {
      if (prev != null && prev.revision == next.revision) return;
      final kind = next.kind;
      if (kind == 'stock_patch') {
        for (final id in next.affectedItemIds) {
          if (id.isNotEmpty) {
            invalidateWarehouseItemSurfacesLight(ref, itemId: id);
          }
        }
      } else if (kind == 'purchase' || kind == 'stock') {
        final ids = next.affectedItemIds.where((id) => id.isNotEmpty).toSet();
        invalidateWarehouseSurfacesLight(ref);
        for (final id in ids) {
          invalidateWarehouseItemSurfacesLight(ref, itemId: id);
        }
      }
    });
    return child;
  }
}
