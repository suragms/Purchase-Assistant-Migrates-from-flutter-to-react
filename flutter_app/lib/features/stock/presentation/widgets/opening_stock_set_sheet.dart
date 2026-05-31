import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/utils/unit_utils.dart';

/// Shows compact bottom sheet to set opening stock.
Future<bool> showOpeningStockSetSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    child: _OpeningStockSetBody(item: item),
  );
  return result == true;
}

class _OpeningStockSetBody extends ConsumerStatefulWidget {
  const _OpeningStockSetBody({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_OpeningStockSetBody> createState() =>
      _OpeningStockSetBodyState();
}

class _OpeningStockSetBodyState extends ConsumerState<_OpeningStockSetBody> {
  bool _saving = false;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;

  late final String _itemId;
  late final String _unit;
  late final double _currentOpening;
  late final bool _locked;

  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _itemId = widget.item['id']?.toString() ?? '';
    final unitRaw = widget.item['stock_unit']?.toString() ??
        widget.item['unit']?.toString() ??
        '';
    _unit = unitRaw.trim().isNotEmpty ? unitRaw.trim().toUpperCase() : '';
    _locked = widget.item['opening_stock_locked'] == true;
    _currentOpening = widget.item['opening_stock_qty'] == null
        ? 0
        : coerceToDouble(widget.item['opening_stock_qty']);
    _qtyCtrl = TextEditingController(
      text: formatStockQtyForUnit(_unit, _currentOpening),
    );
    _notesCtrl = TextEditingController();
    _reasonCtrl = TextEditingController();
    _idempotencyKey =
        'opening-stock:$_itemId:${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final parsed = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid opening stock quantity')),
      );
      return;
    }

    final changed = (parsed - _currentOpening).abs() > 0.001;

    final reasonNeeded = _locked && changed;
    final reason = _reasonCtrl.text.trim();
    if (reasonNeeded && reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reason is required when updating locked opening stock')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).setOpeningStock(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
            qty: parsed,
            override: _locked,
            reason: reasonNeeded ? reason : (reason.isNotEmpty ? reason : null),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            idempotencyKey: _idempotencyKey,
          );

      invalidateWarehouseSurfaces(ref, itemId: _itemId);
      ref.invalidate(openingStockSetupProvider);
      ref.invalidate(stockChangesFeedProvider);

      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCurrent = formatStockQtyForUnit(_unit, _currentOpening);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
            children: [
              Expanded(
                child: Text(
                  widget.item['name']?.toString() ?? 'Item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          if ((widget.item['subcategory_name']?.toString().trim() ?? '').isNotEmpty)
            Text(
              widget.item['subcategory_name'].toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
            ),
          const SizedBox(height: 8),
          Text(
            'Current opening: $displayCurrent ${_unit.isNotEmpty ? _unit : ''}'.trim(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              suffixText: _unit.isEmpty ? null : _unit,
              border: const OutlineInputBorder(),
              labelText: 'Opening stock',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Warehouse notes (optional)',
            ),
          ),
          const SizedBox(height: 14),
          if (_locked) ...[
            Text(
              'Reason (required if changing locked value)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Opening Stock'),
            ),
          ),
        ],
    );
  }
}

