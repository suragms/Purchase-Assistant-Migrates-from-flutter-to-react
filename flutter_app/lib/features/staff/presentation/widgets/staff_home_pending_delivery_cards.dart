import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/staff_home_providers.dart';
import '../../../../core/providers/stock_offline_queue_provider.dart';
import '../../../../core/utils/delivery_offline_actions.dart';
import '../../../../core/utils/snack.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../purchase/providers/trade_purchase_detail_provider.dart';
import '../../../purchase/presentation/widgets/staff_verification_sheet.dart';

/// Up to 3 actionable delivery cards with Mark arrived / Verify.
class StaffHomePendingDeliveryCards extends ConsumerWidget {
  const StaffHomePendingDeliveryCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(staffPendingDeliveriesProvider).valueOrNull ?? [];
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...pending.take(3).map((p) => _DeliveryCard(purchase: p)),
        if (pending.length > 3)
          TextButton(
            onPressed: () => context.push('/staff/receive'),
            child: Text('View all ${pending.length} deliveries'),
          ),
      ],
    );
  }
}

class _DeliveryCard extends ConsumerStatefulWidget {
  const _DeliveryCard({required this.purchase});

  final TradePurchase purchase;

  @override
  ConsumerState<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<_DeliveryCard> {
  bool _busy = false;

  Future<void> _arrive() async {
    final session = ref.read(sessionProvider);
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await markPurchaseArrivedResilient(
        ref: ref,
        businessId: session.primaryBusiness.id,
        purchaseId: widget.purchase.id,
      );
      final queued = result.queued;
      invalidateStaffDeliverySurfacesLight(ref);
      ref.invalidate(tradePurchaseDetailProvider(widget.purchase.id));
      ref.invalidate(stockOfflinePendingCountProvider);
      if (!queued) {
        invalidateWarehouseSurfacesLight(ref);
      }
      if (!queued) {
        unawaited(ref.read(stockOfflineSyncProvider.notifier).syncNow());
      }
      if (mounted) {
        showTopSnack(
          context,
          queued
              ? 'Saved offline — will sync when online'
              : 'Marked arrived',
        );
      }
    } catch (_) {
      if (mounted) {
        showTopSnack(context, 'Could not mark arrived', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (!mounted) return;
    final lines = widget.purchase.lines
        .map(
          (l) => {
            'id': l.id,
            'catalog_item_id': l.catalogItemId,
            'item_name': l.itemName,
            'qty': l.qty,
            'unit': l.unit,
          },
        )
        .toList();
    await showStaffVerificationSheet(
      context: context,
      ref: ref,
      purchaseId: widget.purchase.id,
      lines: lines,
    );
    ref.invalidate(staffPendingDeliveriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.purchase;
    final ds = p.deliveryStatusEnum;
    final summary = p.itemsSummary.isNotEmpty ? p.itemsSummary : p.humanId;
    final qty = p.lines.fold<double>(0, (a, l) => a + l.qty);
    final unit = p.lines.isNotEmpty ? p.lines.first.unit : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatStockQtyNumber(qty)}${unit.isNotEmpty ? ' $unit' : ''} · ${ds.label}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (ds == DeliveryStatus.dispatched ||
                    ds == DeliveryStatus.inTransit ||
                    ds == DeliveryStatus.pending)
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _arrive,
                      child: const Text('Mark arrived'),
                    ),
                  ),
                if (ds.needsStaffAction) ...[
                  if (ds == DeliveryStatus.dispatched ||
                      ds == DeliveryStatus.inTransit ||
                      ds == DeliveryStatus.pending)
                    const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _verify,
                      child: const Text('Verify'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
