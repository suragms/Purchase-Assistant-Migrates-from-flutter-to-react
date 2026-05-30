import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/line_display.dart';
import '../../../purchase/presentation/widgets/purchase_delivery_badge.dart';

/// Owner-style purchase history row for staff — quantities and status only (no ₹).
class StaffPurchaseHistoryRow extends StatelessWidget {
  const StaffPurchaseHistoryRow({
    super.key,
    required this.purchase,
    required this.onTap,
  });

  final TradePurchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sup = (purchase.supplierName ?? 'Supplier').toUpperCase();
    final headline = purchaseHistoryItemHeadline(purchase);
    final pack = purchaseHistoryPackSummary(purchase);
    final df = DateFormat('d MMM yyyy');
    final st = purchase.statusEnum;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: HexaColors.brandBorder),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    pack,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                  const _Dot(),
                  Text(
                    df.format(purchase.purchaseDate),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const _Dot(),
                  Text(
                    purchase.humanId,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _StatusChip(status: st),
                  const SizedBox(width: 6),
                  PurchaseDeliveryBadge(
                    status: purchase.deliveryStatusEnum,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PurchaseStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          color: c,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: TextStyle(color: Color(0xFF94A3B8))),
    );
  }
}
