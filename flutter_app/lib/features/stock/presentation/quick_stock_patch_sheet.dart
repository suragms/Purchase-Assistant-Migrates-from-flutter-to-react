import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/unit_utils.dart';

/// Fast +/- stock adjustment; returns true if saved (for undo snackbar).
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
  late double _current;

  @override
  void initState() {
    super.initState();
    _current = coerceToDouble(widget.item['current_stock']);
  }

  Future<void> _applyDelta(double delta) async {
    if (_saving) return;
    final newQty = _current + delta;
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
      await ref.read(hexaApiProvider).patchStockItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
            newQty: newQty,
            adjustmentType: 'manual',
            reason: delta >= 0 ? 'Quick add' : 'Quick remove',
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockListProvider);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item['unit']?.toString() ?? '';
    final name = widget.item['name']?.toString() ?? 'Item';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Current: ${stockDisplayPrimary(_current, unit)}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _qtyBtn('-5', () => _applyDelta(-5), enabled: !_saving)),
              const SizedBox(width: 8),
              Expanded(child: _qtyBtn('-1', () => _applyDelta(-1), enabled: !_saving)),
              const SizedBox(width: 8),
              Expanded(child: _qtyBtn('+1', () => _applyDelta(1), enabled: !_saving)),
              const SizedBox(width: 8),
              Expanded(child: _qtyBtn('+5', () => _applyDelta(5), enabled: !_saving)),
            ],
          ),
          if (_saving) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _qtyBtn(String label, VoidCallback onTap, {required bool enabled}) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: enabled ? () {
          HapticFeedback.lightImpact();
          onTap();
        } : null,
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
