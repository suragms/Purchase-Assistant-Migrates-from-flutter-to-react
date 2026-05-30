import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/errors/errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../stock/presentation/widgets/stock_update_mode_toggle.dart';
import 'widgets/scan_item_stock_summary_card.dart';

/// Compact post-scan sheet: physical count or system stock + owner alert on staff system edits.
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
    builder: (ctx) => HexaResponsiveSheetViewport(
      compact: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _WarehouseScanActionBody(item: item),
    ),
  );
  return saved == true;
}

class _WarehouseScanActionBody extends ConsumerStatefulWidget {
  const _WarehouseScanActionBody({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_WarehouseScanActionBody> createState() =>
      _WarehouseScanActionBodyState();
}

class _WarehouseScanActionBodyState extends ConsumerState<_WarehouseScanActionBody> {
  final _qtyCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  StockUpdateMode _mode = StockUpdateMode.physical;
  String? _reasonType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cur = coerceToDouble(widget.item['current_stock']);
    _qtyCtl.text = cur == cur.roundToDouble()
        ? '${cur.round()}'
        : cur.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  String get _itemId => widget.item['id']?.toString() ?? '';

  double get _systemQty => coerceToDouble(widget.item['current_stock']);

  double? get _enteredQty => double.tryParse(_qtyCtl.text.trim());

  String get _unit =>
      widget.item['unit']?.toString() ??
      widget.item['stock_unit']?.toString() ??
      '';

  String get _unitLabel => _unit.isNotEmpty ? _unit.toUpperCase() : '';

  double get _diff {
    final q = _enteredQty;
    if (q == null) return 0;
    return _systemQty - q;
  }

  Color get _diffColor {
    final d = _diff.abs();
    if (d < 0.01) return const Color(0xFF3B6D11);
    if (d <= 2) return const Color(0xFFBA7517);
    return const Color(0xFFA32D2D);
  }

  static const _reasons = <String, String>{
    'verification': 'Physical count',
    'correction': 'Correction',
    'sale': 'Sale',
    'damaged': 'Damage',
    'manual': 'Missing',
  };

  Future<void> _save() async {
    if (_saving) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (sessionIsStockReadOnly(session)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read-only account — cannot update stock.')),
      );
      return;
    }
    final qty = _enteredQty;
    if (qty == null || qty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }

    if (_mode == StockUpdateMode.system) {
      if ((_reasonType == null || _reasonType!.isEmpty) &&
          (qty - _systemQty).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a reason for the change')),
        );
        return;
      }
    } else {
      final diff = _systemQty - qty;
      if (diff.abs() > 0.01 && (_reasonType == null || _reasonType!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a reason for the difference')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final bid = session.primaryBusiness.id;
      final note = _notesCtl.text.trim();
      final reasonLabel = _reasons[_reasonType] ?? 'Stock update';

      if (_mode == StockUpdateMode.system) {
        await ref.read(hexaApiProvider).patchStockItem(
              businessId: bid,
              itemId: _itemId,
              newQty: qty,
              adjustmentType: _reasonType ?? 'correction',
              reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
            );
        ref.invalidate(appNotificationsListProvider);
        ref.invalidate(notificationCenterCoordinatorProvider);
      } else {
        final audit = ref.read(activeStockAuditProvider).valueOrNull;
        if (audit != null && audit['id'] != null) {
          await ref.read(hexaApiProvider).upsertStockAuditLine(
                businessId: bid,
                auditId: audit['id'].toString(),
                itemId: _itemId,
                countedQty: qty,
                adjustmentType: _reasonType ?? 'verification',
                reason: reasonLabel,
                notes: note.isEmpty ? null : note,
              );
        } else {
          await ref.read(hexaApiProvider).verifyStockCount(
                businessId: bid,
                itemId: _itemId,
                countedQty: qty,
                adjustmentType: _reasonType ?? 'verification',
                reason: reasonLabel,
                notes: note.isEmpty ? null : note,
              );
        }
      }

      invalidateWarehouseSurfaces(ref, itemId: _itemId);
      ref.invalidate(activeStockAuditProvider);
      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == StockUpdateMode.system
                ? 'System stock updated'
                : 'Physical count saved',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      final offline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      if (offline && _mode == StockUpdateMode.physical) {
        await OfflineStore.queueStockVerify(
          businessId: session.primaryBusiness.id,
          itemId: _itemId,
          countedQty: qty,
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
    final showReason = _mode == StockUpdateMode.system
        ? (_enteredQty != null && (_enteredQty! - _systemQty).abs() > 0.01)
        : _diff.abs() > 0.01;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScanItemStockSummaryCard(item: widget.item),
        const SizedBox(height: 10),
        StockUpdateModeToggle(
          mode: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 6),
        Text(
          stockUpdateModeHint(_mode),
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
        ),
        const SizedBox(height: 10),
        Text(
          _mode == StockUpdateMode.system ? 'System stock' : 'Physical count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final c = _enteredQty ?? _systemQty;
                final next = (c - 1).clamp(0, double.infinity);
                _qtyCtl.text = formatQty(next.toDouble());
                setState(() {});
              },
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: TextField(
                controller: _qtyCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  suffixText: _unitLabel,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final c = _enteredQty ?? _systemQty;
                _qtyCtl.text = formatQty(c + 1);
                setState(() {});
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        if (_mode == StockUpdateMode.physical && _diff.abs() > 0.01) ...[
          const SizedBox(height: 8),
          Text(
            'System ${_formatQty(_systemQty)} $_unitLabel · Diff ${_formatQty(_diff)}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _diffColor),
          ),
        ],
        if (showReason) ...[
          const SizedBox(height: 10),
          const Text('Reason', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Notes (optional)',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/catalog/item/$_itemId');
                },
                child: const Text('Item detail', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: HexaColors.brandPrimary),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _mode == StockUpdateMode.system ? 'Save system' : 'Save count',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatQty(double q) =>
      q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
}

String formatQty(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
