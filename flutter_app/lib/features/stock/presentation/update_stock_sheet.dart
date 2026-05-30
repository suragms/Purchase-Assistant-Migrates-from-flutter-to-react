import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/utils/unit_utils.dart';

const _kAdjustmentTypes = <String, String>{
  'verification': 'Verification',
  'manual': 'Manual',
  'correction': 'Correction',
  'damaged': 'Damaged',
  'expired': 'Expired',
  'purchase': 'Purchase',
};

const _kReasonChips = <String>[
  'Sale',
  'Return',
  'Damaged',
  'Physical count',
  'Transfer',
  'Expired batch',
  'Invoice / data correction',
  'Other',
];

double? _parseQty(String s) {
  final t = s.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

double _qtyFromStockMap(Map<String, dynamic> row) {
  final v = row['current_stock'];
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

/// Bottom sheet: PATCH stock with type, optional reason, and diff preview.
Future<void> showUpdateStockSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  Map<String, dynamic>? stockRow,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => HexaResponsiveSheetViewport(
      compact: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _UpdateStockSheetBody(
        itemId: itemId,
        itemName: itemName,
        seedStock: stockRow,
        parentRef: ref,
      ),
    ),
  );
}

class _UpdateStockSheetBody extends ConsumerStatefulWidget {
  const _UpdateStockSheetBody({
    required this.itemId,
    required this.itemName,
    required this.seedStock,
    required this.parentRef,
  });

  final String itemId;
  final String itemName;
  final Map<String, dynamic>? seedStock;
  final WidgetRef parentRef;

  @override
  ConsumerState<_UpdateStockSheetBody> createState() =>
      _UpdateStockSheetBodyState();
}

class _UpdateStockSheetBodyState extends ConsumerState<_UpdateStockSheetBody> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _reasonCtrl;
  String _adjType = 'verification';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.seedStock;
    final cur = seed != null ? _qtyFromStockMap(seed) : 0.0;
    _qtyCtrl = TextEditingController(
      text: cur == cur.roundToDouble() ? cur.toInt().toString() : cur.toString(),
    );
    _reasonCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final parsed = _parseQty(_qtyCtrl.text);
    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity (0 or more).')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).patchStockItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            newQty: parsed,
            adjustmentType: _adjType,
            reason: _reasonCtrl.text.trim().isEmpty
                ? null
                : _reasonCtrl.text.trim(),
          );
      invalidateWarehouseSurfaces(widget.parentRef, itemId: widget.itemId);
      widget.parentRef.invalidate(catalogItemDetailProvider(widget.itemId));
      widget.parentRef.invalidate(staffTodayActivityProvider);
      widget.parentRef.invalidate(staffTodaySummaryProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock updated')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final stockAsync = widget.seedStock == null
        ? ref.watch(stockItemDetailProvider(widget.itemId))
        : null;
    final baseRow = widget.seedStock ??
        stockAsync?.valueOrNull ??
        <String, dynamic>{};
    final oldQty = baseRow.isNotEmpty ? _qtyFromStockMap(baseRow) : null;
    final newQty = _parseQty(_qtyCtrl.text);
    final unit = (baseRow['unit'] ?? '').toString().trim();

    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Update stock',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              widget.itemName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (stockAsync != null)
              stockAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (_) => const SizedBox.shrink(),
              ),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'New quantity${unit.isNotEmpty ? ' ($unit)' : ''}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              'Adjustment type',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _kAdjustmentTypes.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _adjType == e.key,
                    onSelected: (_) => setState(() => _adjType = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Reason (optional)',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _kReasonChips)
                  ActionChip(
                    label: Text(r),
                    onPressed: () {
                      _reasonCtrl.text = r;
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Notes for audit log',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Preview',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (oldQty == null)
                      Text(
                        'Current on-hand could not be loaded — enter the new total.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Before',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            '${oldQty == oldQty.roundToDouble() ? oldQty.toInt() : oldQty}${unit.isNotEmpty ? ' $unit' : ''}',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'After',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            newQty == null
                                ? '—'
                                : '${newQty == newQty.roundToDouble() ? newQty.toInt() : newQty}${unit.isNotEmpty ? ' $unit' : ''}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      if (newQty != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Change: ${(newQty - oldQty) > 0 ? '+' : ''}${formatStockQtyNumber(newQty - oldQty)}${unit.isNotEmpty ? ' $unit' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save stock'),
            ),
          ],
        ),
    );
  }
}
