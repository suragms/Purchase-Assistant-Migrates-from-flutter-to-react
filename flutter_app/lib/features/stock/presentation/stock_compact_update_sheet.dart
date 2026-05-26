import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/design_system/hexa_responsive.dart';

const _kReasonChips = <(String label, String type)>[
  ('Physical', 'verification'),
  ('Sale', 'sale'),
  ('Damage', 'damaged'),
  ('Correction', 'correction'),
];

Future<bool> showStockCompactUpdateSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _StockCompactUpdateBody(item: item, parentRef: ref),
  );
  return result == true;
}

class _StockCompactUpdateBody extends ConsumerStatefulWidget {
  const _StockCompactUpdateBody({
    required this.item,
    required this.parentRef,
  });

  final Map<String, dynamic> item;
  final WidgetRef parentRef;

  @override
  ConsumerState<_StockCompactUpdateBody> createState() =>
      _StockCompactUpdateBodyState();
}

class _StockCompactUpdateBodyState
    extends ConsumerState<_StockCompactUpdateBody> {
  bool _saving = false;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late double _current;
  String? _reasonType = 'verification';
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _current = coerceToDouble(widget.item['current_stock']);
    if (!_current.isFinite) _current = 0;
    _qtyCtrl = TextEditingController(text: formatStockQtyNumber(_current));
    _notesCtrl = TextEditingController();
    _idempotencyKey =
        'physical:${widget.item['id']}:${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _itemId => widget.item['id']?.toString() ?? '';

  String get _name => widget.item['name']?.toString() ?? 'Item';

  String get _unit =>
      widget.item['stock_unit']?.toString() ??
      widget.item['unit']?.toString() ??
      'piece';

  String get _unitLabel => _unit.isNotEmpty ? _unit.toUpperCase() : '';

  String? get _lastPhysicalLabel {
    if (widget.item['physical_stock_qty'] == null) return null;
    final qty = coerceToDouble(widget.item['physical_stock_qty']);
    if (!qty.isFinite) return null;
    final diff = coerceToDouble(widget.item['physical_stock_difference_qty']);
    final sign = diff >= 0 ? '+' : '';
    return 'Last physical: ${formatStockQtyNumber(qty)} $_unitLabel'
        '${diff.abs() > 0.001 ? ' ($sign${formatStockQtyNumber(diff)} diff)' : ''}';
  }

  Future<void> _save() async {
    if (_reasonType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a reason')),
      );
      return;
    }
    final parsed = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity')),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final note = _notesCtrl.text.trim();
      final reasonLabel =
          _kReasonChips.firstWhere((e) => e.$2 == _reasonType).$1;
      final version =
          int.tryParse(widget.item['stock_version']?.toString() ?? '');
      await ref.read(hexaApiProvider).updatePhysicalStock(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
            countedQty: parsed,
            adjustmentType: _reasonType!,
            reason: reasonLabel,
            notes: note,
            lastSeenStockVersion: version,
            idempotencyKey: _idempotencyKey,
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockListProvider);
      ref.invalidate(stockAuditPeriodProvider);
      ref.invalidate(stockChangesFeedProvider);
      if (_itemId.isNotEmpty) {
        ref.invalidate(stockItemIntelligenceProvider(_itemId));
        ref.invalidate(stockItemActivityProvider(_itemId));
      }
      final reorder = coerceToDouble(widget.item['reorder_level']);
      if (reorder > 0 && parsed <= reorder) {
        final unitLabel = _unit.isNotEmpty ? _unit.toUpperCase() : '';
        await LocalNotificationsService.instance.showLowStockItem(
          itemName: _name,
          detail:
              '${formatStockQtyNumber(parsed)} $unitLabel (reorder ${formatStockQtyNumber(reorder)})',
        );
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

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving && _reasonType != null;
    final stockLabel = stockDisplayPrimary(_current, _unit);
    final lastPhysical = _lastPhysicalLabel;

    return HexaResponsiveSheetViewport(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _name,
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
          Text(
            'Current: $stockLabel',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          if (lastPhysical != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                lastPhysical,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D6B5E),
                ),
              ),
            ),
          const Divider(height: 20),
          const Text(
            'Physical stock',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              suffixText: _unitLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Reason',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in _kReasonChips)
                HexaAccessibleFilterChip(
                  label: chip.$1,
                  selected: _reasonType == chip.$2,
                  onSelected: (_) => setState(() => _reasonType = chip.$2),
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Notes (optional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('UPDATE STOCK'),
            ),
          ),
        ],
      ),
    );
  }
}
