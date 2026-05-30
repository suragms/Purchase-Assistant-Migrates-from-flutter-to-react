import 'package:flutter/material.dart';

import '../../../../core/providers/stock_providers.dart' show StockDeliveryFilter;
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';
import '../../../../shared/widgets/stock_summary_widget.dart';

/// Warehouse table metric formatting (system / purchased / physical / diff / pending).
enum StockDeliveryIndicator { none, pending, delivered }

abstract final class StockRowMetrics {
  static double? purchasedQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['period_purchased_qty']);

  static double? physicalQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['physical_stock_qty']);

  static double? pendingDeliveryQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['pending_delivery_qty']);

  static double? openingQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['opening_stock_qty']);

  static double purchasedLifetimeQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['total_delivered_qty']) ?? 0;

  /// Opening + committed deliveries (spec system column; not raw current_stock).
  static double systemQty(Map<String, dynamic> item) {
    final expected = coerceToDoubleNullable(item['expected_system_qty']);
    if (expected != null && expected.isFinite) return expected;
    final opening = openingQty(item) ?? 0;
    return opening + purchasedLifetimeQty(item);
  }

  /// Ledger on-hand (internal movements); shown only when out of sync.
  static double ledgerStockQty(Map<String, dynamic> item) =>
      coerceToDouble(item['current_stock']);

  static double diffQty(Map<String, dynamic> item) {
    final phys = physicalQty(item);
    if (phys != null && phys.isFinite) {
      return phys - systemQty(item);
    }
    final pd = coerceToDoubleNullable(item['physical_stock_difference_qty']);
    if (pd != null && pd.isFinite) return pd;
    return double.nan;
  }

  static String openingLabel(Map<String, dynamic> item) {
    final opening = coerceToDoubleNullable(item['opening_stock_qty']);
    if (opening == null) return '';
    final u = unit(item);
    return 'Open ${formatStockQtyNumber(opening)}${u.isNotEmpty ? ' $u' : ''}';
  }

  static StockDeliveryIndicator deliveryIndicator(Map<String, dynamic> item) {
    final pendingDel = pendingDeliveryQty(item) ?? 0;
    final hasPending = item['has_pending_order'] == true;
    final po = item['last_purchase_human_id']?.toString().trim() ?? '';
    final deliveredFlag = item['last_purchase_delivered'] == true;
    final undeliveredFlag = item['last_purchase_delivered'] == false;

    if (hasPending || pendingDel > 0.001 || (po.isNotEmpty && undeliveredFlag)) {
      return StockDeliveryIndicator.pending;
    }
    if (po.isNotEmpty && deliveredFlag) {
      return StockDeliveryIndicator.delivered;
    }
    return StockDeliveryIndicator.none;
  }

  static bool matchesDeliveryFilter(
    Map<String, dynamic> item,
    StockDeliveryFilter filter,
  ) {
    if (filter == StockDeliveryFilter.all) return true;
    final ind = deliveryIndicator(item);
    return filter == StockDeliveryFilter.pending
        ? ind == StockDeliveryIndicator.pending
        : ind == StockDeliveryIndicator.delivered;
  }

  static ({int pending, int delivered}) countDeliveryIndicators(
    List<Map<String, dynamic>> items,
  ) {
    var pending = 0;
    var delivered = 0;
    for (final it in items) {
      switch (deliveryIndicator(it)) {
        case StockDeliveryIndicator.pending:
          pending++;
        case StockDeliveryIndicator.delivered:
          delivered++;
        case StockDeliveryIndicator.none:
          break;
      }
    }
    return (pending: pending, delivered: delivered);
  }

  static String deliveryQtyBadge(Map<String, dynamic> item) {
    final pendingDel = pendingDeliveryQty(item) ?? 0;
    if (pendingDel > 0.001) return formatStockQtyNumber(pendingDel);
    final purchased = purchasedQty(item);
    if (purchased != null && purchased > 0.001) {
      return formatStockQtyNumber(purchased);
    }
    return '';
  }

  static String deliveryMetaLine(Map<String, dynamic> item) {
    final parts = <String>[];
    final pendingDel = pendingDeliveryQty(item) ?? 0;
    final hasPending = item['has_pending_order'] == true;
    final delivered = item['last_purchase_delivered'] == true;
    final po = item['last_purchase_human_id']?.toString().trim();
    final days = (item['pending_order_days'] as num?)?.toInt();

    if (hasPending || pendingDel > 0.001) {
      var line = 'Pending truck';
      if (pendingDel > 0.001) {
        line += ' ${formatStockQtyNumber(pendingDel)}';
      }
      if (days != null && days > 0) line += ' · ${days}d';
      if (po != null && po.isNotEmpty) line += ' · $po';
      parts.add(line);
    } else if (delivered) {
      parts.add('Delivered${po != null && po.isNotEmpty ? ' · $po' : ''}');
    }
    return parts.join(' · ');
  }

  static String unit(Map<String, dynamic> item) =>
      (item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece')
          .toUpperCase();

  /// Primary stock qty cell (delegates to [StockSummaryWidget]).
  static Widget stockSummary(
    Map<String, dynamic> item, {
    bool compact = false,
    double fontSize = 17,
  }) {
    final hasPending = item['has_pending_order'] == true;
    final pendingDays = (item['pending_order_days'] as num?)?.toInt();
    return StockSummaryWidget(
      qty: systemQty(item),
      unit: unit(item),
      status: item['stock_status']?.toString(),
      hasPendingOrder: hasPending,
      pendingDays: pendingDays,
      fontSize: fontSize,
      compact: compact,
    );
  }

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
