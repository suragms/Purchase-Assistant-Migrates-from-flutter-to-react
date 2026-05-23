import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/unit_utils.dart';

const _kReasonChips = <(String label, String type)>[
  ('Sale', 'sale'),
  ('Return', 'correction'),
  ('Damaged', 'damaged'),
  ('Physical count', 'verification'),
  ('Purchase', 'purchase'),
  ('Other', 'manual'),
];

/// Fast stock adjustment with set-qty, +/- shortcuts, and reason chips.
Future<bool> showQuickStockPatchSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _QuickStockPatchBody(item: item, parentRef: ref),
  );
  return result == true;
}

class _QuickStockPatchBody extends ConsumerStatefulWidget {
  const _QuickStockPatchBody({required this.item, required this.parentRef});

  final Map<String, dynamic> item;
  final WidgetRef parentRef;

  @override
  ConsumerState<_QuickStockPatchBody> createState() => _QuickStockPatchBodyState();
}

class _QuickStockPatchBodyState extends ConsumerState<_QuickStockPatchBody> {
  bool _saving = false;
  late final TextEditingController _qtyCtrl;
  late double _current;
  String? _reasonType;
  String _reasonNote = '';

  @override
  void initState() {
    super.initState();
    _current = coerceToDouble(widget.item['current_stock']);
    final rounded = _current.roundToDouble();
    _qtyCtrl = TextEditingController(
      text: (_current - rounded).abs() < 0.001
          ? '${rounded.round()}'
          : _current.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  String get _itemId => widget.item['id']?.toString() ?? '';

  String get _unit => widget.item['unit']?.toString() ?? '';

  void _syncQtyField(double qty) {
    _current = qty;
    final rounded = qty.roundToDouble();
    _qtyCtrl.text = (qty - rounded).abs() < 0.001
        ? '${rounded.round()}'
        : qty.toStringAsFixed(1);
  }

  Future<void> _saveQty(double newQty) async {
    if (_saving) return;
    if (newQty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock cannot go below zero')),
      );
      return;
    }
    if (_reasonType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a reason before saving')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final reasonLabel = _kReasonChips
          .firstWhere((e) => e.$2 == _reasonType)
          .$1;
      final note = _reasonNote.trim();
      await ref.read(hexaApiProvider).patchStockItem(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
            newQty: newQty,
            adjustmentType: _reasonType!,
            reason: note.isEmpty ? reasonLabel : note,
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockListProvider);
      ref.invalidate(stockAuditPeriodProvider);
      if (_itemId.isNotEmpty) {
        ref.invalidate(stockItemIntelligenceProvider(_itemId));
      }
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyDelta(double delta) async {
    final newQty = _current + delta;
    _syncQtyField(newQty);
    await _saveQty(newQty);
  }

  Future<void> _setAbsolute() async {
    final parsed = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    _syncQtyField(parsed);
    await _saveQty(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.item['name']?.toString() ?? 'Item';
    final unitLabel = _unit.isNotEmpty ? _unit.toUpperCase() : '';
    final canSave = !_saving && _reasonType != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Current: ${stockDisplayPrimary(_current, _unit)}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Set stock to',
                      suffixText: unitLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final p = double.tryParse(v.replaceAll(',', ''));
                      if (p != null) setState(() => _current = p);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canSave ? _setAbsolute : null,
                  child: const Text('Set'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _qtyBtn('-5', () => _applyDelta(-5), enabled: canSave)),
                const SizedBox(width: 8),
                Expanded(child: _qtyBtn('-1', () => _applyDelta(-1), enabled: canSave)),
                const SizedBox(width: 8),
                Expanded(child: _qtyBtn('+1', () => _applyDelta(1), enabled: canSave)),
                const SizedBox(width: 8),
                Expanded(child: _qtyBtn('+5', () => _applyDelta(5), enabled: canSave)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in _kReasonChips)
                  FilterChip(
                    label: Text(chip.$1, style: const TextStyle(fontSize: 11)),
                    selected: _reasonType == chip.$2,
                    onSelected: (_) => setState(() => _reasonType = chip.$2),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (v) => _reasonNote = v,
            ),
            if (_saving) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qtyBtn(String label, VoidCallback onTap, {required bool enabled}) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: label.startsWith('-')
              ? const Color(0xFFA32D2D)
              : const Color(0xFF3B6D11),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
