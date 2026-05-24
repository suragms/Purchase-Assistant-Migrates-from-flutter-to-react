import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/utils/snack.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../purchase/providers/trade_purchase_detail_provider.dart';

class StaffReceiveShipmentPage extends ConsumerStatefulWidget {
  const StaffReceiveShipmentPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  ConsumerState<StaffReceiveShipmentPage> createState() =>
      _StaffReceiveShipmentPageState();
}

class _StaffReceiveShipmentPageState
    extends ConsumerState<StaffReceiveShipmentPage> {
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _markDelivered(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    setState(() => _saving = true);
    ref.read(tradePurchaseDeliveryOptimisticProvider(p.id).notifier).state =
        true;
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: true,
            deliveryNotes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(tradePurchasesListProvider);
      ref.invalidate(staffPendingDeliveriesProvider);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      if (!mounted) return;
      showTopSnack(context, 'Shipment marked as received');
      context.pop();
    } catch (_) {
      ref.read(tradePurchaseDeliveryOptimisticProvider(p.id).notifier).state =
          null;
      if (mounted) {
        showTopSnack(
          context,
          'Could not save delivery. Check connection and try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(tradePurchaseDetailProvider(widget.purchaseId));
    final optimistic =
        ref.watch(tradePurchaseDeliveryOptimisticProvider(widget.purchaseId));

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Receive shipment'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: detailAsync.when(
        loading: () => const ListSkeleton(rowCount: 5),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load purchase',
          onRetry: () =>
              ref.invalidate(tradePurchaseDetailProvider(widget.purchaseId)),
        ),
        data: (p) {
          final delivered = optimistic ?? p.isDelivered;
          if (delivered) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Already marked delivered',
                      style: HexaDsType.heading(18),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _HeaderCard(purchase: p),
                    const SizedBox(height: 16),
                    Text(
                      'Check each line',
                      style: HexaDsType.heading(16),
                    ),
                    const SizedBox(height: 8),
                    ...p.lines.map((line) => _LineCheckTile(line: line)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Delivery notes (optional)',
                        hintText: 'Shortage, damage, partial receipt…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => context.pop(),
                          child: const Text('Not yet'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _markDelivered(p),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.inventory_rounded),
                          label: const Text('Save & mark delivered'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.purchase});

  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_rounded,
                    color: HexaColors.brandPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.supplierName?.trim().isNotEmpty == true
                        ? p.supplierName!
                        : 'Supplier',
                    style: HexaDsType.heading(17),
                  ),
                ),
              ],
            ),
            if (p.supplierPhone?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(p.supplierPhone!, style: HexaDsType.body(13)),
            ],
            const SizedBox(height: 8),
            Text(
              '${p.humanId}'
              '${p.invoiceNumber != null ? ' · Inv ${p.invoiceNumber}' : ''}',
              style: HexaDsType.body(13, color: HexaDsColors.textMuted),
            ),
            Text(
              DateFormat('EEE, d MMM yyyy').format(p.purchaseDate),
              style: HexaDsType.body(13, color: HexaDsColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCheckTile extends StatelessWidget {
  const _LineCheckTile({required this.line});

  final TradePurchaseLine line;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: true,
        onChanged: null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          line.itemName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          formatLineQtyWeightFromTradeLine(line),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
