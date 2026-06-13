import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/stock/stock_version_retry.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateStockRowSaveSurfaces;
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/stock_providers.dart'
    show
        applyStockListRowPatch,
        patchStockItemInCache,
        stockStatusCountsProvider;
import '../stock_list_row_patch.dart'
    show stockListPatchFromPhysicalCount, stockListPatchFromStockDetail;
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/design_system/hexa_responsive.dart';
import 'widgets/stock_update_mode_toggle.dart';

const _kReasonChips = <(String label, String type)>[
  ('Physical count', 'verification'),
  ('Sale', 'sale'),
  ('Damage', 'damaged'),
  ('Correction', 'correction'),
  ('Wastage', 'damaged'),
];

/// Quick physical stock update (patch / compact update).
Future<bool> showQuickStockActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  StockUpdateMode initialMode = StockUpdateMode.physical,
  bool skipInitialRefresh = false,
  bool refreshItemDetail = false,
}) async {
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _QuickStockActionBody(
      item: item,
      parentRef: ref,
      initialMode: initialMode,
      skipInitialRefresh: skipInitialRefresh,
      refreshItemDetail: refreshItemDetail,
    ),
  );
  return result == true;
}

class _QuickStockActionBody extends ConsumerStatefulWidget {
  const _QuickStockActionBody({
    required this.item,
    required this.parentRef,
    this.initialMode = StockUpdateMode.physical,
    this.skipInitialRefresh = false,
    this.refreshItemDetail = false,
  });

  final Map<String, dynamic> item;
  final WidgetRef parentRef;
  final StockUpdateMode initialMode;
  final bool skipInitialRefresh;
  final bool refreshItemDetail;

  @override
  ConsumerState<_QuickStockActionBody> createState() =>
      _QuickStockActionBodyState();
}

class _QuickStockActionBodyState extends ConsumerState<_QuickStockActionBody> {
  bool _saving = false;
  Map<String, dynamic>? _preSaveItemSnapshot;
  late Map<String, dynamic> _item;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late double _current;
  String? _reasonType = 'verification';
  String _reasonLabel = 'Physical count';
  late StockUpdateMode _mode;
  String? _qtyError;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.item);
    _mode = widget.initialMode;
    _current = _seedQtyForMode(_mode);
    _qtyCtrl = TextEditingController(
      text: formatStockQtyForUnit(_unit, _current),
    );
    _notesCtrl = TextEditingController();
    _qtyCtrl.addListener(_revalidateQty);
    if (!widget.skipInitialRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshItemFromServer());
      });
    }
  }

  double _seedQtyForMode(StockUpdateMode mode) {
    if (mode == StockUpdateMode.physical) {
      final phys = coerceToDoubleNullable(_item['physical_stock_qty']);
      if (phys != null && phys.isFinite && phys >= 0) return phys;
    }
    final sys = coerceToDouble(_item['current_stock']);
    return sys.isFinite ? sys : 0;
  }

  int? _stockVersion() => stockVersionFromItem(_item);

  Future<void> _applyFreshItem(Map<String, dynamic> fresh) async {
    if (!mounted) return;
    setState(() {
      _item = Map<String, dynamic>.from(fresh);
      _current = _seedQtyForMode(_mode);
      _qtyCtrl.text = formatStockQtyForUnit(_unit, _current);
    });
  }

  Future<bool> _refreshItemFromServer() async {
    final session = ref.read(sessionProvider);
    if (session == null) return false;
    try {
      final fresh = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted) return false;
      await _applyFreshItem(fresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onModeChanged(StockUpdateMode mode) {
    setState(() {
      _mode = mode;
      _current = _seedQtyForMode(mode);
      _qtyCtrl.text = formatStockQtyForUnit(_unit, _current);
      _reasonError = null;
      if (mode == StockUpdateMode.physical) {
        _reasonType = 'verification';
        _reasonLabel = 'Physical count';
      } else {
        _reasonType = 'correction';
        _reasonLabel = 'Correction';
      }
      _qtyError = _qtyErrorText();
    });
  }

  double? _parseEnteredQty() {
    final t = _qtyCtrl.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0) return null;
    return v;
  }

  String? _qtyErrorText() {
    if (_parseEnteredQty() != null) return null;
    final t = _qtyCtrl.text.trim();
    if (t.isEmpty) return 'Enter a quantity';
    return 'Enter a valid quantity';
  }

  void _revalidateQty() {
    if (!mounted) return;
    final next = _qtyErrorText();
    setState(() => _qtyError = next);
  }

  bool get _canSave {
    final parsedQty = _parseEnteredQty();
    return !_saving &&
        parsedQty != null &&
        (_mode == StockUpdateMode.physical ||
            (_reasonType != null && _reasonType!.isNotEmpty));
  }

  void _onSavePressed() {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_save());
    });
  }

  @override
  void dispose() {
    _qtyCtrl.removeListener(_revalidateQty);
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _itemId => _item['id']?.toString() ?? '';

  String get _name => _item['name']?.toString() ?? 'Item';

  String get _unit =>
      _item['stock_unit']?.toString() ??
      _item['unit']?.toString() ??
      'piece';

  String get _unitLabel => _unit.isNotEmpty ? _unit.toUpperCase() : '';

  String? get _lastPhysicalLabel {
    if (_item['physical_stock_qty'] == null) return null;
    final qty = coerceToDouble(_item['physical_stock_qty']);
    if (!qty.isFinite) return null;
    final diff = coerceToDouble(_item['physical_stock_difference_qty']);
    final sign = diff >= 0 ? '+' : '';
    return 'Last physical: ${formatStockQtyForUnit(_unit, qty)} $_unitLabel'
        '${diff.abs() > 0.001 ? ' ($sign${formatStockQtyForUnit(_unit, diff)} diff)' : ''}';
  }

  static Future<Map<String, dynamic>?> _persistStockWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required num parsed,
    required String reasonLabel,
    required String? reasonType,
    required String note,
    required int? stockVersion,
  }) async {
    final session = parentRef.read(sessionProvider);
    if (session == null) return null;
    final api = parentRef.read(hexaApiProvider);
    final bid = session.primaryBusiness.id;
    if (mode == StockUpdateMode.system) {
      final detail = await api.patchStockItemWithRetry(
        businessId: bid,
        itemId: itemId,
        newQty: parsed,
        adjustmentType: reasonType ?? 'correction',
        reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
        initialStockVersion: stockVersion,
      );
      parentRef.invalidate(appNotificationsListProvider);
      parentRef.invalidate(notificationCenterCoordinatorProvider);
      return detail;
    }
    return api.recordPhysicalStockCount(
      businessId: bid,
      itemId: itemId,
      countedQty: parsed,
      notes: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
    );
  }

  void _applyOptimisticListPatch(
    Map<String, dynamic>? saved,
    num parsed, {
    WidgetRef? parentRef,
    String? itemId,
    StockUpdateMode? mode,
    Map<String, dynamic>? itemRow,
  }) {
    final ref = parentRef ?? widget.parentRef;
    final id = itemId ?? _itemId;
    final updateMode = mode ?? _mode;
    final row = itemRow ?? _item;
    if (id.isEmpty) return;
    final system = coerceToDouble(row['current_stock']);
    final reorder = row['reorder_level'];
    var patch = updateMode == StockUpdateMode.physical
        ? stockListPatchFromPhysicalCount(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackCountedQty: parsed,
            fallbackSystemQty: system,
          )
        : stockListPatchFromStockDetail(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackQty: parsed,
          );
    if (patch.isEmpty && updateMode == StockUpdateMode.physical) {
      final now = DateTime.now().toUtc().toIso8601String();
      patch = {
        'physical_stock_qty': parsed,
        'physical_stock_difference_qty': parsed - system,
        'physical_stock_counted_at': now,
      };
    }
    if (patch.isEmpty) return;
    if (kDebugMode) {
      debugPrint('[STOCK_CACHE_REFRESH] patchKeys=${patch.keys.toList()}');
    }
    applyStockListRowPatch(ref, itemId: id, patch: patch);
  }

  static void _rollbackOptimisticPatchWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required Map<String, dynamic> preSaveSnapshot,
  }) {
    if (itemId.isEmpty) return;
    final system = coerceToDouble(preSaveSnapshot['current_stock']);
    final phys = coerceToDoubleNullable(preSaveSnapshot['physical_stock_qty']);
    final patch = <String, dynamic>{
      'current_stock': system,
      if (phys != null) 'physical_stock_qty': phys,
      if (phys != null) 'physical_stock_difference_qty': phys - system,
    };
    applyStockListRowPatch(parentRef, itemId: itemId, patch: patch);
  }

  static Future<void> _afterSaveBackgroundWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required num parsed,
    required Map<String, dynamic> itemRow,
    required String itemName,
    required String unit,
    required bool refreshItemDetail,
  }) async {
    final reorder = coerceToDouble(itemRow['reorder_level']);
    final crossedReorder = reorder > 0 && parsed <= reorder;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      invalidateStockRowSaveSurfaces(
        parentRef,
        itemId: itemId,
        immediateListReconcile: false,
        reorderAlert: crossedReorder,
        refreshItemDetail: refreshItemDetail,
      );
    });
    if (crossedReorder) {
      final unitLabel = unit.isNotEmpty ? unit.toUpperCase() : '';
      await LocalNotificationsService.instance.showLowStockItem(
        itemName: itemName,
        detail:
            '${formatStockQtyForUnit(unit, parsed.toDouble())} $unitLabel (reorder ${formatStockQtyForUnit(unit, reorder)})',
      );
    }
  }

  static Future<void> _completeStockSaveAfterPop({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required num parsed,
    required Map<String, dynamic> itemRow,
    required Map<String, dynamic> preSaveSnapshot,
    required String reasonLabel,
    required String? reasonType,
    required String note,
    required int? stockVersion,
    required String itemName,
    required String unit,
    required bool refreshItemDetail,
    ScaffoldMessengerState? messenger,
  }) async {
    try {
      final saved = await _persistStockWithRef(
        parentRef: parentRef,
        itemId: itemId,
        mode: mode,
        parsed: parsed,
        reasonLabel: reasonLabel,
        reasonType: reasonType,
        note: note,
        stockVersion: stockVersion,
      );
      if (kDebugMode) {
        debugPrint(
          '[STOCK_SAVE_SUCCESS] status=${saved?['current_stock'] ?? saved?['physical_stock_qty']}',
        );
      }
      _QuickStockActionBodyState._applyOptimisticListPatchStatic(
        parentRef: parentRef,
        itemId: itemId,
        mode: mode,
        itemRow: itemRow,
        saved: saved,
        parsed: parsed,
      );
      parentRef.invalidate(stockStatusCountsProvider);
      if (mode == StockUpdateMode.system && itemId.isNotEmpty) {
        unawaited(patchStockItemInCache(parentRef, itemId: itemId));
      }
      await _afterSaveBackgroundWithRef(
        parentRef: parentRef,
        itemId: itemId,
        parsed: parsed,
        itemRow: itemRow,
        itemName: itemName,
        unit: unit,
        refreshItemDetail: refreshItemDetail,
      );
    } catch (e) {
      _rollbackOptimisticPatchWithRef(
        parentRef: parentRef,
        itemId: itemId,
        preSaveSnapshot: preSaveSnapshot,
      );
      if (e is StaleStockConflict) {
        try {
          final session = parentRef.read(sessionProvider);
          if (session != null) {
            await parentRef.read(hexaApiProvider).getStockItem(
                  businessId: session.primaryBusiness.id,
                  itemId: itemId,
                );
          }
        } catch (_) {}
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is StaleStockConflict
                ? StaleStockConflict.userMessage
                : e is DioException
                    ? friendlyApiError(e)
                    : userFacingError(e),
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _applyOptimisticListPatchStatic({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required Map<String, dynamic> itemRow,
    required Map<String, dynamic>? saved,
    required num parsed,
  }) {
    final system = coerceToDouble(itemRow['current_stock']);
    final reorder = itemRow['reorder_level'];
    var patch = mode == StockUpdateMode.physical
        ? stockListPatchFromPhysicalCount(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackCountedQty: parsed,
            fallbackSystemQty: system,
          )
        : stockListPatchFromStockDetail(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackQty: parsed,
          );
    if (patch.isEmpty && mode == StockUpdateMode.physical) {
      final now = DateTime.now().toUtc().toIso8601String();
      patch = {
        'physical_stock_qty': parsed,
        'physical_stock_difference_qty': parsed - system,
        'physical_stock_counted_at': now,
      };
    }
    if (patch.isEmpty) return;
    applyStockListRowPatch(parentRef, itemId: itemId, patch: patch);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!mounted) return;

    if (!_canSave) {
      if (!mounted) return;
      setState(() {
        _qtyError = _qtyErrorText();
        if (_mode == StockUpdateMode.system &&
            (_reasonType == null || _reasonType!.isEmpty)) {
          _reasonError = 'Select a reason';
        }
      });
      return;
    }
    final parsed = _parseEnteredQty()!;
    if (_saving) return;
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        '[STOCK_SAVE_START] itemId=$_itemId mode=$_mode qty=$parsed',
      );
    }
    setState(() => _saving = true);
    _preSaveItemSnapshot = Map<String, dynamic>.from(_item);
    final preSaveSnapshot = _preSaveItemSnapshot!;
    final captureItemRow = Map<String, dynamic>.from(_item);
    final captureItemId = _itemId;
    final captureMode = _mode;
    final captureReasonLabel = _reasonLabel;
    final captureReasonType = _reasonType;
    final captureNote = _notesCtrl.text.trim();
    final captureStockVersion = _stockVersion();
    final captureName = _name;
    final captureUnit = _unit;
    final captureRefreshDetail = widget.refreshItemDetail;
    final parentRef = widget.parentRef;
    final messenger = ScaffoldMessenger.maybeOf(context);

    _applyOptimisticListPatch(null, parsed);
    await HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop(true);

    unawaited(
      _completeStockSaveAfterPop(
        parentRef: parentRef,
        itemId: captureItemId,
        mode: captureMode,
        parsed: parsed,
        itemRow: captureItemRow,
        preSaveSnapshot: preSaveSnapshot,
        reasonLabel: captureReasonLabel,
        reasonType: captureReasonType,
        note: captureNote,
        stockVersion: captureStockVersion,
        itemName: captureName,
        unit: captureUnit,
        refreshItemDetail: captureRefreshDetail,
        messenger: messenger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _canSave;
    final stockLabel = stockDisplayPrimary(_current, _unit);
    final lastPhysical = _lastPhysicalLabel;
    final systemQty = coerceToDouble(_item['current_stock']);

    return Column(
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
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
              children: [
                TextSpan(
                  text: _mode == StockUpdateMode.physical
                      ? 'Editing: '
                      : 'System now: ',
                ),
                TextSpan(
                  text: stockLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _mode == StockUpdateMode.physical
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF2563EB),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          if (_mode == StockUpdateMode.physical) ...[
            const SizedBox(height: 3),
            Text(
              'System ledger: ${formatStockQtyForUnit(_unit, systemQty)} $_unitLabel (unchanged until owner syncs)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
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
          if (_item['last_stock_updated_by'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last system edit: ${_item['last_stock_updated_by']}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 10),
          StockUpdateModeToggle(
            mode: _mode,
            onChanged: _onModeChanged,
          ),
          const SizedBox(height: 4),
          Text(
            stockUpdateModeHint(_mode),
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const Divider(height: 20),
          Text(
            _mode == StockUpdateMode.system ? 'System stock' : 'Physical stock',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _qtyError,
            ),
            onSubmitted: (_) {
              if (canSave) _onSavePressed();
            },
          ),
          if (_mode == StockUpdateMode.system) ...[
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
                    selected: _reasonLabel == chip.$1,
                    onSelected: (_) => setState(() {
                      _reasonType = chip.$2;
                      _reasonLabel = chip.$1;
                      _reasonError = null;
                    }),
                    compact: true,
                  ),
              ],
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              child: FilledButton(
                onPressed: canSave && !_saving ? _onSavePressed : null,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _mode == StockUpdateMode.system
                            ? 'SAVE SYSTEM STOCK'
                            : 'SAVE PHYSICAL COUNT',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ),
        ],
      );
  }
}
