import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/utils/unit_utils.dart';

/// Delivery milestones built from purchase API fields (who/when from server).
class PurchaseDeliveryTimeline extends StatelessWidget {
  const PurchaseDeliveryTimeline({super.key, required this.purchase});

  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final events = _events();
    if (events.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Delivery trail',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(height: 8),
        ...events.map((e) => _row(context, cs, e)),
      ],
    );
  }

  List<_DeliveryEvent> _events() {
    final p = purchase;
    final out = <_DeliveryEvent>[];
    final status = p.storedStatus.trim().toLowerCase();
    final stageOrder = <String>[
      'draft',
      'active',
      'approved',
      'ordered',
      'supplier_confirmed',
      'in_transit',
      'arrived',
      'verification_pending',
      'verified',
      'added_to_stock',
      'completed',
    ];
    final statusIndex = stageOrder.indexOf(status);
    bool stageDone(String stage) {
      final i = stageOrder.indexOf(stage);
      if (i < 0 || statusIndex < 0) return false;
      return statusIndex >= i;
    }
    DateTime stageAt(String stage) {
      switch (stage) {
        case 'draft':
        case 'active':
          return p.createdAt ?? p.purchaseDate;
        case 'in_transit':
          return p.dispatchedAt ?? p.updatedAt ?? p.purchaseDate;
        case 'arrived':
          return p.arrivedAt ?? p.updatedAt ?? p.purchaseDate;
        case 'verification_pending':
        case 'verified':
          return p.staffVerifiedAt ?? p.updatedAt ?? p.purchaseDate;
        case 'added_to_stock':
          return p.stockCommittedAt ?? p.deliveredAt ?? p.updatedAt ?? p.purchaseDate;
        case 'completed':
          return p.paidAt ?? p.updatedAt ?? p.purchaseDate;
        default:
          return p.updatedAt ?? p.purchaseDate;
      }
    }
    void addStage(String stage, IconData icon, String label, {String? detail}) {
      if (!stageDone(stage)) return;
      out.add(_DeliveryEvent(at: stageAt(stage), icon: icon, title: label, detail: detail));
    }

    addStage('draft', Icons.drafts_outlined, 'Draft created');
    addStage('active', Icons.play_circle_outline, 'Submitted');
    addStage('approved', Icons.verified_outlined, 'Approved');
    addStage('ordered', Icons.shopping_cart_checkout_outlined, 'Ordered');
    addStage('supplier_confirmed', Icons.task_alt_outlined, 'Supplier confirmed');

    if (p.dispatchedAt != null) {
      final parts = <String>[];
      if ((p.truckNumber ?? '').trim().isNotEmpty) {
        parts.add('Truck ${p.truckNumber!.trim()}');
      }
      if ((p.driverContact ?? '').trim().isNotEmpty) {
        parts.add(p.driverContact!.trim());
      }
      if ((p.dispatchNote ?? '').trim().isNotEmpty) {
        parts.add(p.dispatchNote!.trim());
      }
      out.add(_DeliveryEvent(
        at: p.dispatchedAt!,
        icon: Icons.local_shipping_outlined,
        title: 'Dispatched by supplier',
        detail: parts.isEmpty ? null : parts.join(' · '),
      ));
    }
    addStage(
      'arrived',
      Icons.inventory_2_outlined,
      'Arrived at warehouse',
      detail: p.deliveryNotes,
    );
    addStage(
      'verification_pending',
      Icons.pending_actions_outlined,
      'Verification pending',
    );
    if (p.staffVerifiedAt != null) {
      final who = (p.staffVerifiedByName ?? '').trim();
      var detail = who.isEmpty ? null : 'By $who';
      if (p.staffVerifiedQty != null && p.staffVerifiedQty! > 0) {
        final qty = formatStockQtyNumber(p.staffVerifiedQty!);
        detail = detail == null ? '$qty verified' : '$detail · $qty verified';
      }
      out.add(_DeliveryEvent(
        at: p.staffVerifiedAt!,
        icon: Icons.fact_check_outlined,
        title: 'Staff verification submitted',
        detail: detail,
      ));
    }
    if (p.stockCommittedAt != null || p.isDeliveryCommitted) {
      final at = p.stockCommittedAt ?? p.deliveredAt ?? DateTime.now();
      var detail = 'Stock updated in warehouse';
      if (p.deliveredQtyCommitted != null && p.deliveredQtyCommitted! > 0) {
        detail =
            '${formatStockQtyNumber(p.deliveredQtyCommitted!)} committed to stock';
      }
      out.add(_DeliveryEvent(
        at: at,
        icon: Icons.check_circle_outline_rounded,
        title: 'Committed to stock',
        detail: detail,
      ));
    }
    addStage('completed', Icons.check_circle_rounded, 'Purchase completed');

    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Widget _row(BuildContext context, ColorScheme cs, _DeliveryEvent e) {
    final df = DateFormat('d MMM yyyy · h:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e.icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  df.format(e.at.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  e.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (e.detail != null && e.detail!.trim().isNotEmpty)
                  Text(
                    e.detail!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryEvent {
  const _DeliveryEvent({
    required this.at,
    required this.icon,
    required this.title,
    this.detail,
  });

  final DateTime at;
  final IconData icon;
  final String title;
  final String? detail;
}
