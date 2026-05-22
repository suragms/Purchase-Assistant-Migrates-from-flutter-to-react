import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/reporting/trade_report_aggregate.dart';
import '../../../../core/theme/hexa_colors.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _qtyReadable(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);

/// Warehouse BI summary: purchase value, units, counts, optional comparison line.
class ReportsSummaryCard extends StatelessWidget {
  const ReportsSummaryCard({
    super.key,
    required this.totals,
    required this.periodLabel,
    required this.rangeLabel,
    required this.purchaseCount,
    required this.itemCount,
    required this.supplierCount,
    required this.subcategoryCount,
    this.comparisonLine,
    this.comparisonTrendUp,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  final TradeReportTotals totals;
  final String periodLabel;
  final String rangeLabel;
  final int purchaseCount;
  final int itemCount;
  final int supplierCount;
  final int subcategoryCount;
  final String? comparisonLine;
  final bool? comparisonTrendUp;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      color: HexaColors.brandCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total purchase value',
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: HexaColors.textBody,
                    ),
                  ),
                ),
                if (onToggleCollapse != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                    ),
                    onPressed: onToggleCollapse,
                  ),
              ],
            ),
            Text(
              _inr0(totals.inr),
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: HexaColors.brandPrimary,
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _unitChip('KG', _qtyReadable(totals.kg)),
                  _unitChip('Bags', _qtyReadable(totals.bags)),
                  _unitChip('Boxes', _qtyReadable(totals.boxes)),
                  _unitChip('Tins', _qtyReadable(totals.tins)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$purchaseCount purchases · $supplierCount suppliers · '
                '$itemCount items · $subcategoryCount subcategories',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                '$periodLabel · $rangeLabel',
                style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (comparisonLine != null && comparisonLine!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      comparisonTrendUp == true
                          ? Icons.arrow_upward_rounded
                          : comparisonTrendUp == false
                              ? Icons.arrow_downward_rounded
                              : Icons.remove_rounded,
                      size: 14,
                      color: comparisonTrendUp == false
                          ? const Color(0xFFA32D2D)
                          : const Color(0xFF3B6D11),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        comparisonLine!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _unitChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3EE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0DDD8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.black45)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
