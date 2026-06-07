import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/stock/stock_save_recovery.dart';
import '../../../core/stock/stock_version_retry.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateWarehouseSurfacesAfterStockWrite;
import '../../../core/providers/deferred_invalidation.dart'
    show deferInvalidateDelayed;
import '../../../core/providers/item_detail_providers.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart'
    show stockAuditPeriodProvider;
import '../../../core/providers/stock_providers.dart'
    show
        applyStockListRowPatch,
        stockChangesFeedProvider,
        stockListQueryProvider;
import '../stock_list_row_patch.dart'
    show stockListPatchFromPhysicalCount, stockListPatchFromStockDetail;
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/snack.dart';
import '../../../core/design_system/hexa_responsive.dart';
import 'stock_undo_snackbar.dart';
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
}) async {
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _QuickStockActionBody(
      item: item,
      parentRef: ref,
      parentContext: context,
      initialMode: initialMode,
      skipInitialRefresh: skipInitialRefresh,
    ),
  );
  return result == true;
}

class _QuickStockActionBody extends ConsumerStatefulWidget {
  const _QuickStockActionBody({
    required this.item,
    required this.parentRef,
    required this.parentContext,
    this.initialMode = StockUpdateMode.physical,
    this.skipInitialRefresh = false,
  });

  final Map<String, dynamic> item;
  final WidgetRef parentRef;
  final BuildContext parentContext;
  final StockUpdateMode initialMode;
  final bool skipInitialRefresh;

  @override
  ConsumerState<_QuickStockActionBody> createState() =>
      _QuickStockActionBodyState();
}

class _QuickStockActionBodyState extends ConsumerState<_QuickStockActionBody> {
  bool _saving = false;
  bool _patchApplied = false;
  bool _saveBlockedUntilRetry = false;
  int _refreshGeneration = 0;
  late Map<String, dynamic> _item;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late double _current;
  String? _reasonType = 'verification';
  String _reasonLabel = 'Physical count';
  late StockUpdateMode _mode;
  String? _qtyError;
  String? _reasonError;
  String? _saveError;

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
    final gen = ++_refreshGeneration;
    try {
      final fresh = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted || gen != _refreshGeneration || _saving) return false;
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
    setState(() {
      _qtyError = next;
      if (_saveBlockedUntilRetry && next == null) {
        _saveBlockedUntilRetry = false;
        _saveError = null;
      }
    });
  }

  bool get _canSave {
    final parsedQty = _parseEnteredQty();
    return !_saving &&
        !_saveBlockedUntilRetry &&
        parsedQty != null &&
        (_mode == StockUpdateMode.physical ||
            (_reasonType != null && _reasonType!.isNotEmpty));
  }

  void _onSavePressed() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    unawaited(_save());
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

  Future<Map<String, dynamic>?> _persistStock(
    num parsed, {
    required String idempotencyKey,
    bool force = false,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null) return null;
    final note = _notesCtrl.text.trim();
    final reasonLabel = _reasonLabel;
    final api = ref.read(hexaApiProvider);
    final bid = session.primaryBusiness.id;
    if (_mode == StockUpdateMode.system) {
      final detail = force
          ? await api.patchStockItem(
              businessId: bid,
              itemId: _itemId,
              newQty: parsed,
              adjustmentType: _reasonType ?? 'correction',
              reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
              lastSeenStockVersion: _stockVersion(),
              idempotencyKey: idempotencyKey,
              force: true,
            )
          : await api.patchStockItemWithRetry(
              businessId: bid,
              itemId: _itemId,
              newQty: parsed,
              adjustmentType: _reasonType ?? 'correction',
              reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
              initialStockVersion: _stockVersion(),
              idempotencyKey: idempotencyKey,
            );
      if (!mounted) return null;
      ref.invalidate(appNotificationsListProvider);
      ref.invalidate(notificationCenterCoordinatorProvider);
      return detail;
    }
    final listQ = ref.read(stockListQueryProvider);
    return api.recordPhysicalStockCount(
      businessId: bid,
      itemId: _itemId,
      countedQty: parsed,
      notes: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
      periodStart: listQ.periodStart,
      periodEnd: listQ.periodEnd,
    );
  }

  String _messageForSaveError(Object e) {
    if (e is StaleStockConflict) {
      if (e.currentStock != null && e.currentStock!.isNotEmpty) {
        return 'Stock was updated: current is ${e.currentStock}. Review and retry.';
      }
      return StaleStockConflict.userMessage;
    }
    if (e is StockIntegrityError) return StockIntegrityError.userMessage;
    if (e is DioException) {
      final detail = e.response?.data;
      if (detail is Map) {
        final code = detail['code']?.toString();
        final rawDetail = detail['detail'];
        if (code == 'opening_stock_locked' ||
            rawDetail
                ?.toString()
                .toLowerCase()
                .contains('opening stock is locked') ==
                true) {
          return 'Opening stock is locked — only the owner can adjust this item.';
        }
      } else if (detail is String &&
          detail.toLowerCase().contains('opening stock is locked')) {
        return 'Opening stock is locked — only the owner can adjust this item.';
      }
      return friendlyApiError(e);
    }
    return userFacingError(e);
  }

  Future<bool> _showSaveError(
    Object e, {
    num? parsed,
    DateTime? saveStarted,
  }) async {
    if (parsed != null && saveStarted != null) {
      final recovered = await _verifySaveOnServer(parsed);
      if (recovered != null && mounted) {
        _applyOptimisticListPatch(recovered, parsed);
        unawaited(_afterSaveBackground(parsed));
        try {
          await _completeSaveSuccess(
            recovered,
            parsed,
            saveStarted: saveStarted,
          );
        } catch (err, st) {
          logSilencedApiError(err, st);
          if (mounted) Navigator.of(context).pop(true);
          if (widget.parentContext.mounted) {
            showTopSnack(
              widget.parentContext,
              _mode == StockUpdateMode.system
                  ? 'System stock saved — $_name'
                  : 'Physical count saved — $_name',
            );
          }
        }
        return true;
      }
    }
    final msg = _messageForSaveError(e);
    if (mounted) {
      setState(() {
        _saveError = msg;
        _saveBlockedUntilRetry = true;
      });
    }
    if (widget.parentContext.mounted) {
      showTopSnack(widget.parentContext, msg, isError: true);
    }
    return false;
  }

  bool _persistLooksSuccessful(Map<String, dynamic>? saved, num parsed) {
    if (saved == null) return false;
    if (_mode == StockUpdateMode.physical) {
      return saved.isNotEmpty;
    }
    return saved['current_stock'] != null || saved.isNotEmpty;
  }

  Future<Map<String, dynamic>?> _verifySaveOnServer(num parsed) async {
    final session = ref.read(sessionProvider);
    if (session == null || _itemId.isEmpty) return null;
    try {
      return await verifyStockSaveApplied(
        api: ref.read(hexaApiProvider),
        businessId: session.primaryBusiness.id,
        itemId: _itemId,
        expectedQty: parsed,
        systemLedger: _mode == StockUpdateMode.system,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _tryRecoverAmbiguousSave(
    num parsed,
    Object error,
  ) async {
    if (!stockSaveErrorWorthServerVerify(error)) return null;
    final fresh = await _verifySaveOnServer(parsed);
    if (fresh == null) return null;
    _applyOptimisticListPatch(fresh, parsed);
    return fresh;
  }

  Future<void> _finishRecoveredSave(
    Map<String, dynamic> fresh,
    num parsed, {
    required DateTime saveStarted,
  }) async {
    unawaited(_afterSaveBackground(parsed));
    try {
      await _completeSaveSuccess(fresh, parsed, saveStarted: saveStarted);
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) Navigator.of(context).pop(true);
      if (widget.parentContext.mounted) {
        showTopSnack(
          widget.parentContext,
          _mode == StockUpdateMode.system
              ? 'System stock saved — $_name'
              : 'Physical count saved — $_name',
        );
      }
    }
  }

  Future<void> _completeSaveSuccess(
    Map<String, dynamic> saved,
    num parsed, {
    required DateTime saveStarted,
  }) async {
    final elapsed = DateTime.now().difference(saveStarted);
    const minLoading = Duration(milliseconds: 300);
    if (elapsed < minLoading) {
      await Future<void>.delayed(minLoading - elapsed);
    }
    if (!mounted) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(true);
    if (!widget.parentContext.mounted) return;
    showTopSnack(
      widget.parentContext,
      _mode == StockUpdateMode.system
          ? 'System stock saved — $_name'
          : 'Physical count saved — $_name',
    );
    if (_mode == StockUpdateMode.system) {
      showStockUndoSnackBar(
        context: widget.parentContext,
        ref: widget.parentRef,
        itemId: _itemId,
        itemName: _name,
      );
    }
  }

  void _applyOptimisticListPatch(Map<String, dynamic>? saved, num parsed) {
    if (_patchApplied) return;
    if (_itemId.isEmpty) return;
    final system = coerceToDouble(_item['current_stock']);
    var patch = _mode == StockUpdateMode.physical
        ? stockListPatchFromPhysicalCount(
            saved ?? const {},
            fallbackCountedQty: parsed,
            fallbackSystemQty: system,
          )
        : stockListPatchFromStockDetail(
            saved ?? const {},
            fallbackQty: parsed,
          );
    if (patch.isEmpty && _mode == StockUpdateMode.physical) {
      final now = DateTime.now().toUtc().toIso8601String();
      patch = {
        'physical_stock_qty': parsed,
        'physical_stock_difference_qty': parsed - system,
        'physical_stock_counted_at': now,
      };
    }
    if (patch.isEmpty) return;
    _patchApplied = true;
    applyStockListRowPatch(widget.parentRef, itemId: _itemId, patch: patch);
  }

  void _refreshListInBackground() {
    invalidateWarehouseSurfacesAfterStockWrite(
      widget.parentRef,
      itemId: _itemId,
    );
    deferInvalidateDelayed(
      widget.parentRef,
      itemDetailBundleProvider(_itemId),
      delay: const Duration(milliseconds: 1200),
    );
    deferInvalidateDelayed(widget.parentRef, stockAuditPeriodProvider);
    deferInvalidateDelayed(widget.parentRef, stockChangesFeedProvider);
  }

  Future<void> _afterSaveBackground(num parsed) async {
    try {
      _refreshListInBackground();
      final reorder = coerceToDouble(_item['reorder_level']);
      if (reorder > 0 && parsed <= reorder) {
        final unitLabel = _unit.isNotEmpty ? _unit.toUpperCase() : '';
        await LocalNotificationsService.instance.showLowStockItem(
          itemName: _name,
          detail:
              '${formatStockQtyForUnit(_unit, parsed.toDouble())} $unitLabel (reorder ${formatStockQtyForUnit(_unit, reorder)})',
        );
      }
    } catch (_) {
      // Best-effort background refresh — save already succeeded.
    }
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
    final saveStarted = DateTime.now();
    final idempotencyKey = 'stock-$_itemId-${saveStarted.microsecondsSinceEpoch}';
    ++_refreshGeneration;
    setState(() {
      _saving = true;
      _saveError = null;
      _saveBlockedUntilRetry = false;
      _patchApplied = false;
    });

    Map<String, dynamic>? saved;
    try {
      try {
        saved = await _persistStock(
          parsed,
          idempotencyKey: idempotencyKey,
        );
      } on StaleStockConflict {
        if (!mounted) return;
        await _refreshItemFromServer();
        if (!mounted) return;
        saved = await _persistStock(
          parsed,
          idempotencyKey: idempotencyKey,
          force: true,
        );
      }

      if (!mounted) return;
      if (!_persistLooksSuccessful(saved, parsed)) {
        final recovered = await _verifySaveOnServer(parsed);
        if (recovered != null) {
          saved = recovered;
        } else {
          final recoveredViaError = await _showSaveError(
            StateError(
              'Could not confirm save. Check stock list and retry if needed.',
            ),
            parsed: parsed,
            saveStarted: saveStarted,
          );
          if (recoveredViaError) return;
          return;
        }
      }

      _applyOptimisticListPatch(saved, parsed);
      unawaited(_afterSaveBackground(parsed));

      try {
        await _completeSaveSuccess(
          saved!,
          parsed,
          saveStarted: saveStarted,
        );
      } catch (e, st) {
        logSilencedApiError(e, st);
        if (mounted) Navigator.of(context).pop(true);
        if (widget.parentContext.mounted) {
          showTopSnack(
            widget.parentContext,
            _mode == StockUpdateMode.system
                ? 'System stock saved — $_name'
                : 'Physical count saved — $_name',
          );
        }
      }
    } catch (e, st) {
      final recovered = await _tryRecoverAmbiguousSave(parsed, e);
      if (recovered != null) {
        await _finishRecoveredSave(
          recovered,
          parsed,
          saveStarted: saveStarted,
        );
        return;
      }
      logSilencedApiError(e, st);
      final recoveredViaError = await _showSaveError(
        e,
        parsed: parsed,
        saveStarted: saveStarted,
      );
      if (recoveredViaError) return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _canSave;
    final stockLabel = stockDisplayPrimary(_current, _unit);
    final enteredQty = _parseEnteredQty();
    final editingLabel = enteredQty != null
        ? stockDisplayPrimary(enteredQty, _unit)
        : stockLabel;
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
                  text: _mode == StockUpdateMode.physical
                      ? editingLabel
                      : stockLabel,
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
          if (_saveError != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFB91C1C),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _saveError!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
            if (_saveBlockedUntilRetry) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _saveBlockedUntilRetry = false;
                            _saveError = null;
                          }),
                  child: const Text('Retry save'),
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: (_saving || _saveBlockedUntilRetry) ? null : _onSavePressed,
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
        ],
      );
  }
}
