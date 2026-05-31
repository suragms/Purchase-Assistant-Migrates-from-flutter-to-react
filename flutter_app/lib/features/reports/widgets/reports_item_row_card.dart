import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../shell/reports_layout.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// Compact 72–80px item row for Reports Items tab.
class ReportsItemRowCard extends StatelessWidget {
  const ReportsItemRowCard({
    super.key,
    required this.row,
    this.rateLine,
    this.purchaseCount,
    required this.onTap,
  });

  final TradeReportItemRow row;
  final String? rateLine;
  final int? purchaseCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = row.name.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final qtyParts = <String>[];
    if (row.bags > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('bag', row.bags)} BAG');
    }
    if (row.boxes > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('box', row.boxes)} BOX');
    }
    if (row.tins > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('tin', row.tins)} TIN');
    }
    if (row.kg > 0.001) {
      qtyParts.add('${formatStockQtyForUnit('kg', row.kg)} KG');
    }
    final qtyLine = qtyParts.isEmpty ? '—' : qtyParts.join(' · ');

    return SizedBox(
      height: kReportsRowExtent,
      child: Material(
        color: HexaColors.brandCard,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      HexaColors.brandPrimary.withValues(alpha: 0.12),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: HexaColors.brandPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        qtyLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      if (rateLine != null && rateLine!.isNotEmpty)
                        Text(
                          rateLine!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _inr(row.amountInr),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                    if (purchaseCount != null && purchaseCount! > 0)
                      Text(
                        '$purchaseCount purchases',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
