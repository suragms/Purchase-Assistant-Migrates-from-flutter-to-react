import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/stock/stock_version_retry.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateWarehouseSurfacesLight;
import '../../../../core/providers/stock_providers.dart'
    show applyStockListRowPatch;
import '../../../../core/utils/unit_utils.dart';
import '../../stock_list_row_patch.dart' show stockListPatchFromStockDetail;
import '../stock_undo_snackbar.dart';

/// After a successful barcode lookup — fast +/- stock without leaving scanner flow.
Future<void> showScanStockResultSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: EdgeInsets.fromLTRB(
      HexaOp.pageGutter,
      0,
      HexaOp.pageGutter,
      16,
    ),
    child: _ScanStockResultBody(
      item: item,
      parentContext: context,
      parentRef: ref,
    ),
  );
}

class _ScanStockResultBody extends ConsumerStatefulWidget {
  const _ScanStockResultBody({
    required this.item,
    required this.parentContext,
    required this.parentRef,
  });

  final Map<String, dynamic> item;
  final BuildContext parentContext;
  final WidgetRef parentRef;

  @override
  ConsumerState<_ScanStockResultBody> createState() => _ScanStockResultBodyState();
}

class _ScanStockResultBodyState extends ConsumerState<_ScanStockResultBody> {
  bool _saving = false;
  late Map<String, dynamic> _item;
  late double _current;

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
    _current = coerceToDouble(_item['current_stock']);
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
      final id = _item['id']?.toString() ?? '';
      final api = ref.read(hexaApiProvider);
      final bid = session.primaryBusiness.id;
      final saved = await api.patchStockItemWithRetry(
        businessId: bid,
        itemId: id,
        newQty: newQty,
        adjustmentType: 'manual',
        reason: delta >= 0 ? 'Scan quick add' : 'Scan quick remove',
        initialStockVersion: stockVersionFromItem(_item),
      );
      applyStockListRowPatch(
        widget.parentRef,
        itemId: id,
        patch: stockListPatchFromStockDetail(saved, fallbackQty: newQty),
      );
      invalidateWarehouseSurfacesLight(ref, itemId: id);
      if (!mounted) return;
      setState(() => _current = newQty);
      await HapticFeedback.lightImpact();
      if (!widget.parentContext.mounted) return;
      final name = _item['name']?.toString() ?? 'Item';
      showStockUndoSnackBar(
        context: widget.parentContext,
        ref: widget.parentRef,
        itemId: id,
        itemName: name,
      );
    } on StaleStockConflict {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(StaleStockConflict.userMessage)),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update stock. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _item['name']?.toString() ?? 'Item';
    final unit = _item['unit']?.toString() ?? '';
    final id = _item['id']?.toString() ?? '';
    final stockLine = stockDisplayPrimary(_current, unit);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            Text(name, style: HexaOp.cardTitle(context)),
            const SizedBox(height: 4),
            Text(
              'Stock: $stockLine',
              style: HexaOp.body(context),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _qtyBtn('-5', () => _applyDelta(-5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _qtyBtn('-1', () => _applyDelta(-1)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _qtyBtn('+1', () => _applyDelta(1)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _qtyBtn('+5', () => _applyDelta(5)),
                ),
              ],
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () {
                      Navigator.pop(context);
                      if (id.isNotEmpty) {
                        widget.parentContext.push(
                          '/catalog/item/$id?source=scan',
                        );
                      }
                    },
              child: const Text('Full item details'),
            ),
            TextButton(
              onPressed: _saving || id.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.parentContext.push(
                        '/barcode/print/${Uri.encodeComponent(id)}',
                      );
                    },
              child: const Text('Print label'),
            ),
          ],
    );
  }

  Widget _qtyBtn(String label, VoidCallback onTap) {
    return SizedBox(
      height: HexaOp.buttonHeight,
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
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
