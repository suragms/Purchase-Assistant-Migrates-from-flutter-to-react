import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';

/// Warehouse table metric formatting (system / purchased / physical / diff / pending).
abstract final class StockRowMetrics {
  static double? purchasedQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['period_purchased_qty']);

  static double? physicalQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['physical_stock_qty']);

  static double? pendingDeliveryQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['pending_delivery_qty']);

  static double stockQty(Map<String, dynamic> item) {
    // Stock column must show backend system/on-hand stock truth.
    // Physical count is displayed separately in item snapshot/workflows.
    return coerceToDouble(item['current_stock']);
  }

  static double diffQty(Map<String, dynamic> item) {
    final wh = coerceToDoubleNullable(item['warehouse_diff_qty']);
    if (wh != null && wh.isFinite) return wh;
    final phys = physicalQty(item);
    if (phys != null && phys.isFinite) {
      return phys - stockQty(item);
    }
    final purchased = purchasedQty(item);
    if (purchased == null) return double.nan;
    return stockQty(item) - purchased;
  }

  static String unit(Map<String, dynamic> item) =>
      (item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece')
          .toUpperCase();

  static String qtyLine(double? qty, String unit) {
    if (qty == null || !qty.isFinite) return '—';
    return '${formatStockQtyNumber(qty)}\n$unit';
  }

  static String signedDiffLine(double diff, String unit) {
    if (!diff.isFinite) return '—';
    if (diff.abs() < 0.001) {
      return '0\nBalanced';
    }
    final sign = diff > 0 ? '+' : '';
    final intent = diff > 0 ? 'Excess' : 'Deficit';
    return '$sign${formatStockQtyNumber(diff)} $unit\n$intent';
  }

  static Color diffColor(double diff) {
    if (!diff.isFinite || diff.abs() < 0.001) {
      return const Color(0xFF64748B);
    }
    return diff > 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
  }

  static String inlineStatusLabel(Map<String, dynamic> item) {
    final st = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    return switch (stockDisplayStatusFromApi(st)) {
      StockDisplayStatus.out => 'Out',
      StockDisplayStatus.low => 'Low stock',
      StockDisplayStatus.ok => 'Healthy',
      StockDisplayStatus.normal => 'Healthy',
    };
  }

  static Color inlineStatusColor(Map<String, dynamic> item) {
    final st = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    return stockNumberColor(stockDisplayStatusFromApi(st));
  }
}
