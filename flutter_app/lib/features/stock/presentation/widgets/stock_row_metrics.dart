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

  /// Owner row subtitle: committed + in-transit purchase qty.
  static String ownerDeliveryMetaLine(Map<String, dynamic> item) {
    final parts = <String>[];
    final delivered = purchasedLifetimeQty(item);
    final pending = pendingDeliveryQty(item) ?? 0;
    final u = unit(item);
    if (delivered > 0.001) {
      parts.add('Delivered ${formatStockQtyNumber(delivered)} $u');
    }
    if (pending > 0.001) {
      parts.add('Pending ${formatStockQtyNumber(pending)} $u');
    }
    return parts.join(' · ');
  }

  /// Authoritative ledger on-hand — primary display metric for warehouse lists.
  static double ledgerQty(Map<String, dynamic> item) =>
      coerceToDouble(item['current_stock']);

  /// Opening + committed inbound movements (audit/reconciliation only).
  static double expectedSystemQty(Map<String, dynamic> item) {
    final expected = coerceToDoubleNullable(item['expected_system_qty']);
    if (expected != null && expected.isFinite) return expected;
    final opening = openingQty(item) ?? 0;
    final quick = coerceToDoubleNullable(item['total_quick_purchase_qty']) ?? 0;
    return opening + purchasedLifetimeQty(item) + quick;
  }

  /// Display SSOT for operational stock rows (ledger on-hand).
  static double systemQty(Map<String, dynamic> item) => ledgerQty(item);

  /// Ledger on-hand alias for clarity in owner analytics.
  static double ledgerStockQty(Map<String, dynamic> item) => ledgerQty(item);

  static double diffQty(Map<String, dynamic> item) {
    final phys = physicalQty(item);
    if (phys != null && phys.isFinite) {
      return phys - ledgerQty(item);
    }
    final pd = coerceToDoubleNullable(item['physical_stock_difference_qty']);
    if (pd != null && pd.isFinite) return pd;
    return double.nan;
  }

  /// Compact warehouse table cell — ledger on-hand.
  static String systemCellLabel(Map<String, dynamic> item) =>
      formatStockQtyForUnit(unit(item), ledgerQty(item));

  /// Compact warehouse table cell — physical qty or em dash.
  static String physicalCellLabel(Map<String, dynamic> item) {
    final phys = physicalQty(item);
    if (phys == null || !phys.isFinite) return '—';
    return formatStockQtyForUnit(unit(item), phys);
  }

  /// Compact warehouse table cell — signed physical minus system, or em dash.
  static String diffCellLabel(Map<String, dynamic> item) {
    final diff = diffQty(item);
    if (!diff.isFinite) return '—';
    if (diff.abs() < 0.001) return '0';
    final sign = diff > 0 ? '+' : '';
    return '$sign${formatStockQtyForUnit(unit(item), diff)}';
  }

  /// Inline truck / delivered cue for item cell (qty + days, no extra column).
  static Widget? inlineDeliveryCue(Map<String, dynamic> item) {
    final cell = pendingCellDisplay(item);
    if (cell.primary == '—') return null;

    final kind = deliveryIndicator(item);
    final icon = kind == StockDeliveryIndicator.delivered
        ? Icons.check_circle_rounded
        : Icons.local_shipping_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: cell.color),
        if (cell.primary != '•' && cell.primary != '✓') ...[
          const SizedBox(width: 2),
          Text(
            cell.primary,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: cell.color,
              height: 1,
            ),
          ),
        ],
        if (cell.secondary != null) ...[
          const SizedBox(width: 2),
          Text(
            cell.secondary!,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: cell.color.withValues(alpha: 0.9),
              height: 1,
            ),
          ),
        ],
      ],
    );
  }

  /// Pending truck qty (+ optional days) for inline item-row cue.
  static ({String primary, String? secondary, Color color}) pendingCellDisplay(
    Map<String, dynamic> item,
  ) {
    const pendingColor = Color(0xFFEA580C);
    const deliveredColor = Color(0xFF16A34A);
    const muted = Color(0xFF94A3B8);
    final u = unit(item);
    final pending = pendingDeliveryQty(item) ?? 0;
    final days = (item['pending_order_days'] as num?)?.toInt();
    final kind = deliveryIndicator(item);

    if (pending > 0.001 || kind == StockDeliveryIndicator.pending) {
      final qty = pending > 0.001 ? pending : 0.0;
      return (
        primary: qty > 0.001 ? formatStockQtyForUnit(u, qty) : '•',
        secondary: days != null && days > 0 ? '${days}d' : null,
        color: pendingColor,
      );
    }
    if (kind == StockDeliveryIndicator.delivered) {
      return (
        primary: '✓',
        secondary: days != null && days > 0 ? '${days}d' : null,
        color: deliveredColor,
      );
    }
    return (primary: '—', secondary: null, color: muted);
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
    final days = (item['pending_order_days'] as num?)?.toInt();

    if (hasPending || pendingDel > 0.001) {
      var line = 'Pending truck';
      if (pendingDel > 0.001) {
        line += ' ${formatStockQtyNumber(pendingDel)}';
      }
      if (days != null && days > 0) line += ' · ${days}d';
      parts.add(line);
    } else if (delivered) {
      parts.add('Delivered');
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
      qty: ledgerQty(item),
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

  /// Relative label for [last_stock_updated_at] (list row info line).
  static String? relativeUpdatedLabel(Map<String, dynamic> item) {
    final raw = item['last_stock_updated_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Updated ${diff.inDays}d ago';
    return 'Updated ${dt.day}/${dt.month}';
  }
}
