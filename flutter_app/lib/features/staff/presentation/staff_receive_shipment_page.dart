import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import 'package:dio/dio.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/delivery_offline_actions.dart';
import '../../../core/utils/snack.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../purchase/presentation/widgets/staff_verification_sheet.dart';
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
  final _truckCtrl = TextEditingController();
  final _driverCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  final _missingCtrl = TextEditingController();
  bool _brokerConfirmed = false;
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _truckCtrl.dispose();
    _driverCtrl.dispose();
    _damageCtrl.dispose();
    _missingCtrl.dispose();
    super.dispose();
  }

  double? _parseOptionalQty(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _submitReceive(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    setState(() => _saving = true);
    try {
      final bid = session.primaryBusiness.id;
      final ds = p.deliveryStatusEnum;
      if (ds == DeliveryStatus.stockCommitted || p.isDeliveryCommitted) {
        if (mounted) {
          showTopSnack(context, 'Already committed to stock');
          context.pop();
        }
        return;
      }
      if (ds.readyForOwnerCommit) {
        if (mounted) {
          showTopSnack(
            context,
            'Waiting for owner to commit verified qty to stock',
          );
          context.pop();
        }
        return;
      }

      if (ds == DeliveryStatus.pending ||
          ds == DeliveryStatus.dispatched ||
          ds == DeliveryStatus.inTransit) {
        final damageQty = _parseOptionalQty(_damageCtrl.text);
        final missingQty = _parseOptionalQty(_missingCtrl.text);
        await markPurchaseArrivedResilient(
          ref: ref,
          businessId: bid,
          purchaseId: p.id,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          truckNumber: _truckCtrl.text.trim(),
          driverContact: _driverCtrl.text.trim(),
          damageQty: damageQty,
          missingQty: missingQty,
          brokerConfirmed: _brokerConfirmed,
        );
        if (mounted &&
            ((damageQty ?? 0) > 0 || (missingQty ?? 0) > 0)) {
          showTopSnack(
            context,
            'Discrepancy recorded in arrival notes — owner will review',
          );
        }
      }

      final lineMaps = [
        for (final l in p.lines)
          {
            'id': l.id,
            'catalog_item_id': l.catalogItemId,
            'item_name': l.itemName,
            'qty': l.qty,
            'unit': l.unit,
          }
      ];
      if (!mounted) return;
      final verified = await showStaffVerificationSheet(
        context: context,
        ref: ref,
        purchaseId: p.id,
        lines: lineMaps,
      );
      invalidateStaffDeliverySurfaces(ref);
      if (verified) {
        if (mounted) {
          showTopSnack(
            context,
            'Received — quantities verified. Owner will commit stock to warehouse.',
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not save receipt. Try again.',
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
          final ds = p.deliveryStatusEnum;
          if (ds == DeliveryStatus.stockCommitted || p.isDeliveryCommitted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Stock already committed',
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
          if (ds.readyForOwnerCommit) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFF7C3AED), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Waiting for owner approval',
                      style: HexaDsType.heading(18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You verified this shipment. Owner must commit to stock.',
                      textAlign: TextAlign.center,
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
                      controller: _truckCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Truck number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _driverCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Driver name / contact',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _damageCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Damage qty',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _missingCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Missing qty',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Broker confirmed delivery'),
                      value: _brokerConfirmed,
                      onChanged: (v) => setState(() => _brokerConfirmed = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Arrival notes (optional)',
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mark arrival and verify counts. Stock updates only after owner commits.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
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
                              onPressed: _saving ? null : () => _submitReceive(p),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.fact_check_outlined),
                              label: const Text('Arrive & verify'),
                            ),
                          ),
                        ],
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
    final df = DateFormat('d MMM yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              purchase.humanId,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            if (purchase.supplierName != null) ...[
              const SizedBox(height: 4),
              Text(purchase.supplierName!),
            ],
            const SizedBox(height: 4),
            Text(
              df.format(purchase.purchaseDate),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
      child: ListTile(
        title: Text(line.itemName),
        subtitle: Text(
          '${line.qty.toStringAsFixed(0)} ${line.unit}',
        ),
      ),
    );
  }
}
