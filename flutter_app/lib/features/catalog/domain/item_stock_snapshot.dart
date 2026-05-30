import 'package:flutter/material.dart';

import '../../../core/json_coerce.dart';

class ItemStockSnapshot {
  const ItemStockSnapshot({
    required this.unitLabel,
    required this.openingQty,
    required this.purchasedQty,
    required this.physicalQty,
    required this.systemQty,
    required this.diffQty,
    required this.reorderLevel,
    required this.hasPendingIncoming,
    required this.pendingIncomingDays,
    required this.lastUpdatedAt,
    required this.lastUpdatedBy,
    required this.needsVerification,
  });

  final String unitLabel;
  final double openingQty;
  final double purchasedQty;
  final double physicalQty;
  final double systemQty;
  final double diffQty;
  final double reorderLevel;
  final bool hasPendingIncoming;
  final int? pendingIncomingDays;
  final DateTime? lastUpdatedAt;
  final String? lastUpdatedBy;
  final bool needsVerification;

  /// Creates a snapshot from a `StockListItemOut`-shaped row map.
  ///
  /// This is used by low-stock operations lists, where the backend already
  /// enriches rows with physical/system quantities, reorder level, and
  /// pending-incoming metadata.
  factory ItemStockSnapshot.fromStockListRow(
    Map<String, dynamic> row,
  ) {
    final unitRaw =
        (row['stock_unit'] ?? row['unit'] ?? '').toString().trim();
    final unitLabel = unitRaw.isNotEmpty ? unitRaw.toUpperCase() : 'PIECE';

    final openingQty = coerceToDouble(row['opening_stock_qty']);
    final purchasedQty = coerceToDouble(row['period_purchased_qty']);

    final systemQty = coerceToDouble(row['current_stock']);
    final physicalQtyRaw = row['physical_stock_qty'];
    final physicalQty = physicalQtyRaw == null ? systemQty : coerceToDouble(physicalQtyRaw);

    final reorderLevel = coerceToDouble(row['reorder_level']);
    final hasPendingIncoming = row['has_pending_order'] == true;
    final pendingIncomingDays =
        row['pending_order_days'] is num ? (row['pending_order_days'] as num).toInt() : null;

    final diffQty = (row['physical_stock_difference_qty'] as num?)
            ?.toDouble() ??
        (row['warehouse_diff_qty'] as num?)?.toDouble() ??
        (physicalQty - systemQty);

    final lastUpdatedAtRaw = row['last_stock_updated_at']?.toString();
    final lastUpdatedAt = lastUpdatedAtRaw != null
        ? DateTime.tryParse(lastUpdatedAtRaw)?.toLocal()
        : null;
    final lastUpdatedBy = row['last_stock_updated_by']?.toString();

    final needsVerification = row['needs_verification'] == true;

    return ItemStockSnapshot(
      unitLabel: unitLabel,
      openingQty: openingQty,
      purchasedQty: purchasedQty,
      physicalQty: physicalQty,
      systemQty: systemQty,
      diffQty: diffQty,
      reorderLevel: reorderLevel,
      hasPendingIncoming: hasPendingIncoming,
      pendingIncomingDays: pendingIncomingDays,
      lastUpdatedAt: lastUpdatedAt,
      lastUpdatedBy: (lastUpdatedBy != null && lastUpdatedBy.trim().isNotEmpty)
          ? lastUpdatedBy.trim()
          : null,
      needsVerification: needsVerification,
    );
  }

  ItemStockStatus get status {
    if (systemQty < -0.0001) return ItemStockStatus.negative;
    if (needsVerification || !diffQty.isFinite) {
      return ItemStockStatus.pendingVerification;
    }
    if (diffQty.abs() > 0.0001) return ItemStockStatus.mismatch;
    if (systemQty <= 0.0001) return ItemStockStatus.outOfStock;
    if (reorderLevel > 0.0001 && systemQty <= reorderLevel) {
      return ItemStockStatus.lowStock;
    }
    return ItemStockStatus.healthy;
  }

  String diffLabel() {
    if (!diffQty.isFinite) {
      if (needsVerification) return 'Verify needed';
      if (openingQty <= 0.0001 && systemQty <= 0.0001) return 'Opening not set';
      return 'Count pending';
    }
    final abs = diffQty.abs();
    if (abs <= 0.0001) {
      if (needsVerification) return 'Verify needed';
      return 'No difference';
    }
    final n = _fmt(abs);
    if (diffQty < 0) return '$n $unitLabel missing';
    return '$n $unitLabel extra';
  }

  Color statusColor() => switch (status) {
        ItemStockStatus.healthy => const Color(0xFF2E7D32),
        ItemStockStatus.lowStock => const Color(0xFFB45309),
        ItemStockStatus.outOfStock => const Color(0xFFC62828),
        ItemStockStatus.negative => const Color(0xFF7F1D1D),
        ItemStockStatus.mismatch => const Color(0xFFA32D2D),
        ItemStockStatus.pendingVerification => const Color(0xFF1565C0),
      };

  String statusChipLabel() => switch (status) {
        ItemStockStatus.healthy => 'HEALTHY',
        ItemStockStatus.lowStock => 'LOW STOCK',
        ItemStockStatus.outOfStock => 'OUT OF STOCK',
        ItemStockStatus.negative => 'NEGATIVE STOCK',
        ItemStockStatus.mismatch => 'MISMATCH',
        ItemStockStatus.pendingVerification => 'PENDING VERIFICATION',
      };
}

enum ItemStockStatus {
  healthy,
  lowStock,
  outOfStock,
  negative,
  mismatch,
  pendingVerification,
}

String _fmt(double n) {
  final s = n.toStringAsFixed(n.abs() < 1 ? 2 : 0);
  return s.replaceAll(RegExp(r'\.0+$'), '').replaceAll(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
}

