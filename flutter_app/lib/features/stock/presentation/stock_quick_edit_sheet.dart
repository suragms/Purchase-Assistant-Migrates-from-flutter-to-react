import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/design_system/hexa_responsive.dart';

const _kReasons = <String, ({String type, String label})>{
  'Purchase': (type: 'purchase', label: 'Purchase'),
  'Sale': (type: 'sale', label: 'Sale'),
  'Usage': (type: 'usage', label: 'Usage'),
  'Damage': (type: 'damaged', label: 'Damage'),
  'Correction': (type: 'correction', label: 'Correction'),
  'Transfer': (type: 'transfer', label: 'Transfer'),
};

Future<bool> showStockQuickEditSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _StockQuickEditBody(item: item),
  );
  return result == true;
}

class _StockQuickEditBody extends ConsumerStatefulWidget {
  const _StockQuickEditBody({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_StockQuickEditBody> createState() =>
      _StockQuickEditBodyState();
}

class _StockQuickEditBodyState extends ConsumerState<_StockQuickEditBody> {
  bool _saving = false;
  late double _current;
  late final TextEditingController _manualCtrl;
  String _reason = 'Purchase';

  @override
  void initState() {
    super.initState();
    _current = coerceToDouble(widget.item['current_stock']);
    _manualCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveQty(double newQty) async {
    if (_saving) return;
    if (newQty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock cannot go below zero')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final id = widget.item['id']?.toString() ?? '';
      final reasonMeta = _kReasons[_reason]!;
      await ref.read(hexaApiProvider).patchStockItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
            newQty: newQty,
            adjustmentType: reasonMeta.type,
            reason: reasonMeta.label,
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockListProvider);
      ref.invalidate(stockItemIntelligenceProvider(id));
      ref.invalidate(bulkStockListProvider);
      if (context.mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadStateErrorSubtitle(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _applyDelta(double delta) => _saveQty(_current + delta);

  void _applyManual() {
    final t = _manualCtrl.text.trim().replaceAll(',', '');
    final v = double.tryParse(t);
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    _saveQty(v);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item['unit']?.toString() ?? '';
    final name = widget.item['name']?.toString() ?? 'Item';

    return HexaResponsiveSheetViewport(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
            'Current: ${stockDisplayPrimary(_current, unit)}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _qtyBtn('+1', () => _applyDelta(1)),
              _qtyBtn('+5', () => _applyDelta(5)),
              _qtyBtn('+10', () => _applyDelta(10)),
              _qtyBtn('-1', () => _applyDelta(-1)),
              _qtyBtn('-5', () => _applyDelta(-5)),
              _qtyBtn('-10', () => _applyDelta(-10)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Manual quantity',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Text('Reason', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _kReasons.keys)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ChoiceChip(
                    label: Text(r, style: const TextStyle(fontSize: 12)),
                    selected: _reason == r,
                    onSelected:
                        _saving ? null : (_) => setState(() => _reason = r),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _applyManual,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: 72,
      height: 44,
      child: FilledButton(
        onPressed: _saving
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
        style: FilledButton.styleFrom(
          backgroundColor: label.startsWith('-')
              ? const Color(0xFFA32D2D)
              : const Color(0xFF3B6D11),
          padding: EdgeInsets.zero,
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );
  }
}
