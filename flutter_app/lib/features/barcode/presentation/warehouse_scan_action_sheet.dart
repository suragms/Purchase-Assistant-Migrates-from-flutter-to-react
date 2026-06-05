import 'dart:async';

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
import '../../../core/providers/business_aggregates_invalidation.dart'
    show
        invalidateWarehouseItemSurfacesLight,
        invalidateWarehouseSurfacesLight;
import '../../../core/providers/stock_providers.dart' show applyStockListRowPatch;
import '../../stock/stock_list_row_patch.dart'
    show stockListPatchFromPhysicalCount, stockListPatchFromStockDetail;
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/stock/stock_version_retry.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../stock/presentation/widgets/stock_update_mode_toggle.dart';
import 'widgets/scan_item_stock_summary_card.dart';

/// Compact post-scan sheet: physical count or system stock + owner alert on staff system edits.
Future<bool> showWarehouseScanActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final saved = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _WarehouseScanActionBody(item: item),
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
  late Map<String, dynamic> _item;
  StockUpdateMode _mode = StockUpdateMode.physical;
  String? _reasonType;
  bool _saving = false;
  bool _actionChosen = false;
  String? _qtyError;
  String? _reasonError;

  void _seedQtyFromItem() {
    final session = ref.read(sessionProvider);
    final privileged = session != null && sessionIsPrivilegedStockRole(session);
    final phys = coerceToDoubleNullable(
      _item['physical_stock_qty'] ?? _item['physical_count_qty'],
    );
    final cur = privileged
        ? coerceToDouble(_item['current_stock'])
        : (phys ?? coerceToDouble(_item['current_stock']));
    _qtyCtl.text = cur == cur.roundToDouble()
        ? '${cur.round()}'
        : cur.toStringAsFixed(1);
  }

  Future<void> _refreshItemFromServer() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final fresh = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted) return;
      setState(() {
        _item = Map<String, dynamic>.from(fresh);
        _seedQtyFromItem();
      });
    } catch (_) {}
  }

  Future<void> _refreshAfterSave() async {
    invalidateWarehouseSurfacesLight(ref);
    invalidateWarehouseItemSurfacesLight(ref, itemId: _itemId);
    ref.invalidate(activeStockAuditProvider);
  }

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
    _seedQtyFromItem();
    _qtyCtl.addListener(_revalidateQty);
    final hasStockRow = widget.item['current_stock'] != null;
    if (!hasStockRow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshItemFromServer());
      });
    }
  }

  @override
  void dispose() {
    _qtyCtl.removeListener(_revalidateQty);
    _qtyCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  double? _parseEnteredQty() {
    final t = _qtyCtl.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0) return null;
    return v;
  }

  String? _qtyErrorText() {
    if (_parseEnteredQty() != null) return null;
    final t = _qtyCtl.text.trim();
    if (t.isEmpty) return 'Enter a quantity';
    return 'Enter a valid quantity';
  }

  void _revalidateQty() {
    if (!mounted) return;
    final next = _qtyErrorText();
    if (next != _qtyError) {
      setState(() => _qtyError = next);
    }
  }

  void _onSavePressed() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_save());
    });
  }

  String get _itemId => _item['id']?.toString() ?? '';

  double get _systemQty => coerceToDouble(_item['current_stock']);

  double? get _enteredQty => _parseEnteredQty();

  String get _unit =>
      _item['unit']?.toString() ??
      _item['stock_unit']?.toString() ??
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
    final qty = _parseEnteredQty();
    if (qty == null) {
      setState(() {
        _qtyError = _qtyErrorText();
      });
      return;
    }

    if (_mode == StockUpdateMode.system) {
      if ((_reasonType == null || _reasonType!.isEmpty) &&
          (qty - _systemQty).abs() > 0.01) {
        setState(() => _reasonError = 'Select a reason for the change');
        return;
      }
    } else {
      final diff = _systemQty - qty;
      if (diff.abs() > 0.01 && (_reasonType == null || _reasonType!.isEmpty)) {
        setState(() => _reasonError = 'Select a reason for the difference');
        return;
      }
      if (diff.abs() > 0.5) {
        final direction = diff > 0 ? 'decrease' : 'increase';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'Stock will $direction by ${_formatQty(diff.abs())} ${_unitLabel.isEmpty ? 'units' : _unitLabel}',
            ),
            content: const Text(
              'This updates system stock to match your physical count. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final bid = session.primaryBusiness.id;
      final note = _notesCtl.text.trim();
      final reasonLabel = _reasons[_reasonType] ?? 'Stock update';

      final privileged = sessionIsPrivilegedStockRole(session);

      if (_mode == StockUpdateMode.system) {
        if (!privileged) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('System stock change'),
              content: const Text(
                'System stock is the ERP ledger. Owner/admin will be notified. '
                'Use physical count for floor stock unless you are correcting the ledger.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (ok != true) {
            setState(() => _saving = false);
            return;
          }
        }
        final api = ref.read(hexaApiProvider);
        final saved = await api.patchStockItemWithRetry(
          businessId: bid,
          itemId: _itemId,
          newQty: qty,
          adjustmentType: _reasonType ?? 'correction',
          reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
          initialStockVersion: stockVersionFromItem(_item),
        );
        if (!mounted) return;
        ref.invalidate(appNotificationsListProvider);
        ref.invalidate(notificationCenterCoordinatorProvider);
        applyStockListRowPatch(
          ref,
          itemId: _itemId,
          patch: stockListPatchFromStockDetail(saved, fallbackQty: qty),
        );
      } else {
        Map<String, dynamic>? saved;
        final audit = ref.read(activeStockAuditProvider).valueOrNull;
        if (audit != null && audit['id'] != null) {
          saved = await ref.read(hexaApiProvider).upsertStockAuditLine(
                businessId: bid,
                auditId: audit['id'].toString(),
                itemId: _itemId,
                countedQty: qty,
                adjustmentType: _reasonType ?? 'verification',
                reason: reasonLabel,
                notes: note.isEmpty ? null : note,
              );
        } else {
          saved = await ref.read(hexaApiProvider).verifyStockCountWithRetry(
                businessId: bid,
                itemId: _itemId,
                countedQty: qty,
                adjustmentType: _reasonType ?? 'verification',
                reason: reasonLabel,
                notes: note.isEmpty ? null : note,
                initialStockVersion: stockVersionFromItem(_item),
              );
        }
        if (!mounted) return;
        applyStockListRowPatch(
          ref,
          itemId: _itemId,
          patch: stockListPatchFromPhysicalCount(saved),
        );
      }

      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
      unawaited(_refreshAfterSave());
    } on StaleStockConflict {
      if (!mounted) return;
      await _refreshItemFromServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(StaleStockConflict.userMessage),
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        SnackBar(
          content: Text(loadStateErrorSubtitle(e)),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loadStateErrorSubtitle(e)),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isReadOnly = session == null || sessionIsStockReadOnly(session);
    final privileged =
        session != null && sessionIsPrivilegedStockRole(session);
    final parsedQty = _parseEnteredQty();
    final canSave = !_saving && parsedQty != null;
    final showReason = _mode == StockUpdateMode.system
        ? (parsedQty != null && (parsedQty - _systemQty).abs() > 0.01)
        : _diff.abs() > 0.01;

    final lpQty = coerceToDoubleNullable(_item['last_purchase_qty']);
    final lpUnit = _item['last_purchase_unit']?.toString().trim() ?? _unit;
    final lpDateRaw = _item['last_purchase_date']?.toString();
    final lpDate = lpDateRaw != null ? DateTime.tryParse(lpDateRaw) : null;
    final supplier = _item['supplier_name']?.toString().trim() ?? '';

    if (isReadOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanItemStockSummaryCard(item: _item),
          const SizedBox(height: 12),
          Text(
            'Read-only account. Ask owner/admin to update stock.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    if (!_actionChosen) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanItemStockSummaryCard(item: _item),
          const SizedBox(height: 10),
          const Text(
            'What would you like to do?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.inventory_2_outlined,
            title: 'Update Physical Count',
            subtitle: 'Most common: compare floor count with system',
            onTap: () => setState(() {
              _mode = StockUpdateMode.physical;
              _actionChosen = true;
            }),
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.article_outlined,
            title: 'View Full Details',
            subtitle: 'Open full item page with history',
            onTap: () {
              Navigator.pop(context);
              context.push('/catalog/item/$_itemId');
            },
          ),
          const SizedBox(height: 8),
          _actionTile(
            icon: Icons.shopping_cart_checkout_outlined,
            title: 'Quick Purchase',
            subtitle: 'Create purchase draft for this item',
            onTap: () {
              Navigator.pop(context);
              context.push('/purchase/new');
            },
          ),
          if (privileged) ...[
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.tune_rounded,
              title: 'System Stock Adjust',
              subtitle: 'Ledger correction (owner/admin use only)',
              onTap: () => setState(() {
                _mode = StockUpdateMode.system;
                _actionChosen = true;
              }),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _actionChosen = false;
                      }),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
            ),
          ],
        ),
        ScanItemStockSummaryCard(item: _item),
        if (lpQty != null && lpQty > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 16, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last Purchased: ${formatQty(lpQty)} ${lpUnit.toUpperCase()}'
                    '${supplier.isNotEmpty ? ' from $supplier' : ''}'
                    '${lpDate != null ? ' (${ScanItemStockSummaryCard.daysAgoLabel(lpDate)})' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (!privileged && _mode == StockUpdateMode.system)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: const Text(
              'Staff: system stock edits notify owner/admin. Prefer physical count for daily checks.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        StockUpdateModeToggle(
          mode: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 6),
        Text(
          privileged
              ? stockUpdateModeHint(_mode)
              : (_mode == StockUpdateMode.system
                  ? 'System ledger — owner notified on save.'
                  : 'Physical count — does not change system stock.'),
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
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  suffixText: _unitLabel,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  errorText: _qtyError,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (canSave) _onSavePressed();
                },
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
                onSelected: (_) => setState(() {
                  _reasonType = e.key;
                  _reasonError = null;
                }),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          if (_reasonError != null) ...[
            const SizedBox(height: 6),
            Text(
              _reasonError!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB91C1C),
              ),
            ),
          ],
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
                onPressed: canSave ? _onSavePressed : null,
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

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: HexaColors.brandPrimary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatQty(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);
