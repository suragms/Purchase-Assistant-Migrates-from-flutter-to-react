import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/theme/hexa_colors.dart';
import '../shell/reports_layout.dart';

String _inr(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

/// ~76px purchase row card for Reports Purchases tab.
class ReportsPurchaseRowCard extends StatelessWidget {
  const ReportsPurchaseRowCard({
    super.key,
    required this.purchase,
    required this.onTap,
  });

  final TradePurchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    final lineCount = purchase.lines.length;
    final supplier = purchase.supplierName ?? 'Supplier';
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
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 18, color: HexaColors.brandPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        supplier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${purchase.humanId} · ${df.format(purchase.purchaseDate)} · $lineCount lines',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _inr(purchase.totalAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: HexaColors.brandPrimary,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportsPurchaseRowCardSkeleton extends StatelessWidget {
  const ReportsPurchaseRowCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kReportsRowExtent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(height: 12, color: Colors.grey.shade200),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 160,
                    color: Colors.grey.shade100,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
