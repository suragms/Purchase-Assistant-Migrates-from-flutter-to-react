import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/item_detail_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../domain/item_stock_snapshot.dart';

class ItemStockSnapshotCard extends ConsumerWidget {
  const ItemStockSnapshotCard({
    super.key,
    required this.itemId,
  });

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isOwner = session != null && sessionHasOwnerDashboard(session);
    final stock = ref.watch(stockItemDetailProvider(itemId)).valueOrNull ?? const <String, dynamic>{};
    final intel = ref.watch(stockItemIntelligenceProvider(itemId)).valueOrNull ?? const <String, dynamic>{};
    if (stock.isEmpty && intel.isEmpty) {
      return const SizedBox.shrink();
    }

    final unitRaw = (stock['stock_unit'] ?? stock['unit'] ?? 'piece').toString();
    final unit = unitRaw.trim().isEmpty ? 'piece' : unitRaw.trim();
    final unitLabel = unit.toUpperCase();

    final openingQty = coerceToDouble(stock['opening_stock_qty']);
    final purchasedQty = coerceToDouble(intel['period_purchased_qty'] ?? stock['period_purchased_qty']);
    final physicalQty = coerceToDouble(stock['physical_stock_qty']);
    final systemQty = coerceToDouble(stock['current_stock']);
    final reorder = coerceToDouble(stock['reorder_level']);
    final needsVerification = stock['needs_verification'] == true || intel['needs_verification'] == true;
    final hasPending = stock['has_pending_order'] == true;
    final pendingDays = stock['pending_order_days'] is num ? (stock['pending_order_days'] as num).toInt() : null;
    final pendingDeliveryQty = coerceToDouble(stock['pending_delivery_qty']);
    final openingSetAt = stock['opening_stock_set_at'];
    final openingLocked = stock['opening_stock_locked'] == true;
    final showOpeningCta = openingSetAt == null && !openingLocked;

    final diff =
        (stock['physical_stock_difference_qty'] as num?)?.toDouble() ??
        (stock['warehouse_diff_qty'] as num?)?.toDouble() ??
        (physicalQty - systemQty);

    final updatedAtRaw = stock['last_stock_updated_at']?.toString();
    final updatedAt = updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw)?.toLocal() : null;
    final updatedBy = stock['last_stock_updated_by']?.toString();

    final snap = ItemStockSnapshot(
      unitLabel: unitLabel,
      openingQty: openingQty,
      purchasedQty: purchasedQty,
      physicalQty: physicalQty,
      systemQty: systemQty,
      diffQty: diff,
      reorderLevel: reorder,
      hasPendingIncoming: hasPending,
      pendingIncomingDays: pendingDays,
      lastUpdatedAt: updatedAt,
      lastUpdatedBy: (updatedBy != null && updatedBy.trim().isNotEmpty) ? updatedBy.trim() : null,
      needsVerification: needsVerification,
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Warehouse stock snapshot', style: HexaOp.cardTitle(context)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: snap.statusColor().withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: snap.statusColor().withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    snap.diffLabel(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      color: snap.statusColor(),
                    ),
                  ),
                ),
              ],
            ),
            if (showOpeningCta) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Opening stock not set',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: HexaColors.warning,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showOpeningStockSheet(
                        context,
                        ref,
                        itemId,
                        systemQty,
                      ),
                      child: const Text('Set opening stock'),
                    ),
                  ],
                ),
              ),
            ],
            if (systemQty > 0.001 &&
                (needsVerification ||
                    (stock['physical_stock_counted_at'] == null &&
                        physicalQty <= 0.001))) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Text(
                  'Physical count not done yet — verify warehouse qty before trusting system stock.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: HexaColors.warning,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (isOwner)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(hexaApiProvider).recomputeItemStock(
                            businessId: session.primaryBusiness.id,
                            itemId: itemId,
                          );
                      ref.invalidate(stockItemDetailProvider(itemId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('System stock recomputed')),
                        );
                      }
                    } on DioException catch (e) {
                      if (context.mounted) {
                        final isConflict = e.response?.statusCode == 409;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isConflict
                                  ? 'Recompute already in progress. Please wait and refresh.'
                                  : 'Could not recompute stock',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Recompute'),
                ),
              ),
            if (isOwner) const SizedBox(height: 6),
            _row(
              leftLabel: 'System stock',
              leftValue: _qty(systemQty),
              rightLabel: 'Physical stock',
              rightValue: _qty(physicalQty),
              unitLabel: unitLabel,
              emphasisRight: true,
              warningRight: systemQty > 0.001 && physicalQty <= 0.001,
            ),
            const SizedBox(height: 8),
            _row(
              leftLabel: 'Opening stock',
              leftValue: _qty(openingQty),
              rightLabel: 'Purchased (period)',
              rightValue: _qty(purchasedQty),
              unitLabel: unitLabel,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: Color(0xFFE65100),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Reorder level:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: reorder > 0.0001
                        ? Text(
                            '${_qty(reorder)} $unitLabel',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )
                        : Text(
                            'Not set',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: () => _showReorderSheet(context, ref, itemId, reorder),
                    child: Text(reorder > 0.0001 ? 'Edit' : 'Set'),
                  ),
                ],
              ),
            ),
            if (pendingDeliveryQty > 0.001) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Pending delivery',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_qty(pendingDeliveryQty)} $unitLabel',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasPending && pendingDays != null && pendingDays > 0
                          ? 'Not in warehouse until bill is received · $pendingDays d on order'
                          : 'Not in warehouse until bill is received',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (reorder > 0.0001)
                  _pill('Reorder at ${_qty(reorder)} $unitLabel'),
                if (hasPending)
                  _pill(pendingDays != null && pendingDays > 0
                      ? 'Incoming pending • $pendingDays d'
                      : 'Incoming pending'),
                if (needsVerification) _pill('Verification needed'),
                if (updatedAt != null)
                  _pill(
                    updatedBy != null
                        ? 'Updated ${_timeAgo(updatedAt)} • $updatedBy'
                        : 'Updated ${_timeAgo(updatedAt)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _qty(double n) {
    if (!n.isFinite) return '—';
    if (n.abs() < 0.001) return '0';
    return formatStockQtyNumber(n);
  }

  static Widget _pill(String t) {
    return Chip(
      label: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  static Widget _row({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
    required String unitLabel,
    bool emphasisRight = false,
    bool warningRight = false,
  }) {
    Widget cell(
      String label,
      String value, {
      bool emphasis = false,
      bool warning = false,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: warning
                ? const Color(0xFFFFFBEB)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: warning ? HexaColors.warning : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: emphasis ? 20 : 18,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    unitLabel,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF475569)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(leftLabel, leftValue),
        const SizedBox(width: 8),
        cell(
          rightLabel,
          rightValue,
          emphasis: emphasisRight,
          warning: warningRight,
        ),
      ],
    );
  }

  static String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static void _showOpeningStockSheet(
    BuildContext context,
    WidgetRef ref,
    String itemId,
    double current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _OpeningStockSheet(itemId: itemId, currentStock: current),
    );
  }

  static void _showReorderSheet(
    BuildContext context,
    WidgetRef ref,
    String itemId,
    double current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReorderLevelSheet(itemId: itemId, current: current),
    );
  }
}

class _OpeningStockSheet extends ConsumerStatefulWidget {
  const _OpeningStockSheet({required this.itemId, required this.currentStock});

  final String itemId;
  final double currentStock;

  @override
  ConsumerState<_OpeningStockSheet> createState() => _OpeningStockSheetState();
}

class _OpeningStockSheetState extends ConsumerState<_OpeningStockSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentStock > 0) {
      _ctrl.text = widget.currentStock.toStringAsFixed(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null || val < 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).setOpeningStock(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            qty: val,
          );
      ref.invalidate(stockItemDetailProvider(widget.itemId));
      ref.invalidate(itemDetailBundleProvider(widget.itemId));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set Opening Stock',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening quantity',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('SET OPENING STOCK'),
          ),
        ],
      ),
    );
  }
}

class _ReorderLevelSheet extends ConsumerStatefulWidget {
  const _ReorderLevelSheet({required this.itemId, required this.current});

  final String itemId;
  final double current;

  @override
  ConsumerState<_ReorderLevelSheet> createState() => _ReorderLevelSheetState();
}

class _ReorderLevelSheetState extends ConsumerState<_ReorderLevelSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.current > 0) {
      _ctrl.text = widget.current.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null || val < 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            patchReorderLevel: true,
            reorderLevel: val,
          );
      ref.invalidate(stockItemDetailProvider(widget.itemId));
      ref.invalidate(itemDetailBundleProvider(widget.itemId));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set Reorder Level',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Reorder quantity',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('SAVE REORDER LEVEL'),
          ),
        ],
      ),
    );
  }
}

