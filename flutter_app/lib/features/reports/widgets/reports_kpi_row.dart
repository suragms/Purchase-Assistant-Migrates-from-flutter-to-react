import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// Single-row KPI strip for Overview (~64px cells).
class ReportsKpiRow extends StatelessWidget {
  const ReportsKpiRow({
    super.key,
    required this.totals,
    required this.itemCount,
    required this.supplierCount,
  });

  final TradeReportTotals totals;
  final int itemCount;
  final int supplierCount;

  @override
  Widget build(BuildContext context) {
    final qtyParts = <String>[];
    if (totals.bags > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('bag', totals.bags)} BAG');
    }
    if (totals.boxes > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('box', totals.boxes)} BOX');
    }
    if (totals.tins > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('tin', totals.tins)} TIN');
    }
    if (totals.kg > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('kg', totals.kg)} KG');
    }
    final qtyLine = qtyParts.isEmpty ? '—' : qtyParts.join(' · ');

    return Row(
      children: [
        Expanded(
          child: _KpiCell(
            label: 'Purchase',
            value: _inr(totals.inr),
            subtitle: 'Value',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _KpiCell(
            label: 'Total qty',
            value: qtyLine.split(' · ').first,
            subtitle: qtyParts.length > 1 ? '+${qtyParts.length - 1}' : 'Units',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _KpiCell(
            label: 'Items',
            value: '$itemCount',
            subtitle: 'In period',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _KpiCell(
            label: 'Suppliers',
            value: '$supplierCount',
            subtitle: 'Active',
          ),
        ),
      ],
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: HexaColors.brandCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: HexaColors.brandPrimary,
                height: 1,
              ),
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
