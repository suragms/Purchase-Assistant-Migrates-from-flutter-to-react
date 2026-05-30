import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/errors/errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/providers/stock_providers.dart';
import 'widgets/scan_item_stock_summary_card.dart';

/// Compact post-scan warehouse sheet: counted stock, reconciliation, reasons, ledger preview.
Future<bool> showWarehouseScanActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.88,
      builder: (_, scroll) => _WarehouseScanActionBody(
        item: item,
        scrollController: scroll,
      ),
    ),
  );
  return saved == true;
}

class _WarehouseScanActionBody extends ConsumerStatefulWidget {
  const _WarehouseScanActionBody({
    required this.item,
    required this.scrollController,
  });

  final Map<String, dynamic> item;
  final ScrollController scrollController;

  @override
  ConsumerState<_WarehouseScanActionBody> createState() =>
      _WarehouseScanActionBodyState();
}

class _WarehouseScanActionBodyState extends ConsumerState<_WarehouseScanActionBody> {
  final _countedCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  String? _reasonType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cur = coerceToDouble(widget.item['current_stock']);
    _countedCtl.text = cur == cur.roundToDouble()
        ? '${cur.round()}'
        : cur.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _countedCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  String get _itemId => widget.item['id']?.toString() ?? '';

  double get _systemQty => coerceToDouble(widget.item['current_stock']);

  double? get _countedQty => double.tryParse(_countedCtl.text.trim());

  double get _diff {
    final c = _countedQty;
    if (c == null) return 0;
    return _systemQty - c;
  }

  Color get _diffColor {
    final d = _diff.abs();
    if (d < 0.01) return const Color(0xFF3B6D11);
    if (d <= 2) return const Color(0xFFBA7517);
    return const Color(0xFFA32D2D);
  }

  String _insightLine() {
    final d = _diff;
    if (d.abs() < 0.01) return 'Count matches system stock.';
    if (d > 0) return 'Possible unrecorded usage or missing stock.';
    return 'Counted stock is higher than system — check recent purchases.';
  }

  static const _reasons = <String, String>{
    'sale': 'Sale',
    'usage': 'Usage',
    'damaged': 'Damage',
    'transfer': 'Transfer',
    'correction': 'Correction',
    'manual': 'Missing',
    'purchase': 'Purchase received',
  };

  Future<void> _save() async {
    if (_saving) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (sessionIsStockReadOnly(session)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Read-only account — cannot update stock from scan.'),
        ),
      );
      return;
    }
    final counted = _countedQty;
    if (counted == null || counted < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid counted quantity')),
      );
      return;
    }
    final diff = _systemQty - counted;
    if (diff.abs() > 0.01 && (_reasonType == null || _reasonType!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a reason for the difference')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bid = session.primaryBusiness.id;
      final reasonLabel = _reasons[_reasonType] ?? 'Physical count';
      final audit = ref.read(activeStockAuditProvider).valueOrNull;
      if (audit != null && audit['id'] != null) {
        await ref.read(hexaApiProvider).upsertStockAuditLine(
              businessId: bid,
              auditId: audit['id'].toString(),
              itemId: _itemId,
              countedQty: counted,
              adjustmentType: _reasonType ?? 'verification',
              reason: reasonLabel,
              notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
            );
      } else {
        await ref.read(hexaApiProvider).verifyStockCount(
              businessId: bid,
              itemId: _itemId,
              countedQty: counted,
              adjustmentType: _reasonType ?? 'verification',
              reason: reasonLabel,
              notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
            );
      }
      invalidateWarehouseSurfaces(ref, itemId: _itemId);
      ref.invalidate(activeStockAuditProvider);
      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      final offline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      if (offline) {
        await OfflineStore.queueStockVerify(
          businessId: session.primaryBusiness.id,
          itemId: _itemId,
          countedQty: counted,
          reason: _reasons[_reasonType] ?? 'Physical count',
          adjustmentType: _reasonType ?? 'verification',
          notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline — will sync when connected')),
        );
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadStateErrorSubtitle(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadStateErrorSubtitle(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemId = _itemId;
    final intel = ref.watch(stockItemIntelligenceProvider(itemId));
    final unit = widget.item['unit']?.toString() ??
        widget.item['default_unit']?.toString() ??
        '';
    final unitLabel = unit.isNotEmpty ? unit.toUpperCase() : '';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        controller: widget.scrollController,
        children: [
          ScanItemStockSummaryCard(item: widget.item),
          const SizedBox(height: 12),
          Text(
            'Update stock (counted)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: 'Decrease count',
                onPressed: () {
                  final c = _countedQty ?? _systemQty;
                  final next = (c - 1).clamp(0, double.infinity);
                  _countedCtl.text = next == next.roundToDouble()
                      ? '${next.round()}'
                      : next.toStringAsFixed(1);
                  setState(() {});
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: TextField(
                  controller: _countedCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: unitLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Increase count',
                onPressed: () {
                  final c = _countedQty ?? _systemQty;
                  final next = c + 1;
                  _countedCtl.text = next == next.roundToDouble()
                      ? '${next.round()}'
                      : next.toStringAsFixed(1);
                  setState(() {});
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _reconciliationBlock(unitLabel),
          if (_diff.abs() > 0.01) ...[
            const SizedBox(height: 10),
            Text(
              _insightLine(),
              style: TextStyle(fontSize: 12, color: _diffColor, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text(
              'Reason (required)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _reasons.entries.map((e) {
                final sel = _reasonType == e.key;
                return FilterChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11)),
                  selected: sel,
                  onSelected: (_) => setState(() => _reasonType = e.key),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Notes (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 12),
          intel.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, __) => const SizedBox.shrink(),
            data: (m) => _miniLedger(m),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/stock/intelligence/$itemId');
                  },
                  child: const Text('Full detail', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reconciliationBlock(String unitLabel) {
    final c = _countedQty ?? _systemQty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _diffColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _diffColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('System: ${formatQty(_systemQty)} $unitLabel',
              style: const TextStyle(fontSize: 12)),
          Text('Counted: ${formatQty(c)} $unitLabel',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Difference: ${formatQty(_diff)} $unitLabel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _diffColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniLedger(Map<String, dynamic> intel) {
    final adj = intel['recent_adjustments'];
    if (adj is! List || adj.isEmpty) {
      return const Text('No recent ledger entries', style: TextStyle(fontSize: 12));
    }
    final rows = adj.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent ledger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 6),
        ...rows.map((r) {
          final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
          final type = m['adjustment_type']?.toString() ?? '';
          final oldQ = coerceToDouble(m['old_qty']);
          final newQ = coerceToDouble(m['new_qty']);
          final delta = newQ - oldQ;
          final sign = delta >= 0 ? '+' : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$sign${formatQty(delta)} · $type',
              style: const TextStyle(fontSize: 11),
            ),
          );
        }),
        TextButton(
          onPressed: () =>
              context.push('/catalog/item/$_itemId?tab=history'),
          child: const Text('Open full ledger'),
        ),
      ],
    );
  }
}

String formatQty(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
