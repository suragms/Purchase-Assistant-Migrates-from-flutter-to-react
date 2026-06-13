import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/purchase/purchase_stock_commit_preflight.dart';
import '../../../../core/utils/snack.dart';
import '../../../../shared/widgets/bag_default_unit_hint.dart';

/// Inline unit setup when commit-stock is blocked — saves catalog default_unit.
Future<bool> showQuickCatalogUnitSetupSheet(
  BuildContext context, {
  required WidgetRef ref,
  required PurchaseStockCommitIssue issue,
  Map<String, dynamic>? catalogRow,
}) {
  return showHexaBottomSheet<bool>(
    context: context,
    child: QuickCatalogUnitSetupSheet(
      issue: issue,
      catalogRow: catalogRow,
    ),
  ).then((v) => v == true);
}

class QuickCatalogUnitSetupSheet extends ConsumerStatefulWidget {
  const QuickCatalogUnitSetupSheet({
    super.key,
    required this.issue,
    this.catalogRow,
  });

  final PurchaseStockCommitIssue issue;
  final Map<String, dynamic>? catalogRow;

  @override
  ConsumerState<QuickCatalogUnitSetupSheet> createState() =>
      _QuickCatalogUnitSetupSheetState();
}

class _QuickCatalogUnitSetupSheetState
    extends ConsumerState<QuickCatalogUnitSetupSheet> {
  late String _unit;
  final _kgCtrl = TextEditingController();
  bool _saving = false;
  String? _kgError;

  static const _units = ['kg', 'bag', 'box', 'tin', 'piece'];

  @override
  void initState() {
    super.initState();
    _unit = suggestCatalogUnitForStockCommitIssue(
      widget.issue,
      widget.catalogRow,
    );
    final kpb = widget.catalogRow?['default_kg_per_bag'] ??
        widget.catalogRow?['unit_resolution'] is Map
            ? (widget.catalogRow!['unit_resolution'] as Map)['kg_per_bag']
            : null;
    if (kpb != null) {
      _kgCtrl.text = kpb.toString();
    } else {
      final parsed = parseKgPerBagFromName(widget.issue.itemName);
      if (parsed != null && _unit == 'bag') {
        _kgCtrl.text = parsed.toString();
      }
    }
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final catalogId = widget.issue.catalogItemId?.trim();
    if (catalogId == null || catalogId.isEmpty) {
      if (mounted) {
        showTopSnack(context, 'Link this line to a catalog item first.', isError: true);
      }
      return;
    }
    if (_unit == 'bag') {
      final kg = parseOptionalKgPerBag(_kgCtrl.text);
      if (kg == null || kg <= 0) {
        setState(() => _kgError = 'Kg per bag is required when unit is bag');
        return;
      }
    }
    setState(() {
      _kgError = null;
      _saving = true;
    });
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      final kgParsed =
          _unit == 'bag' ? parseOptionalKgPerBag(_kgCtrl.text) : null;
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: catalogId,
            includeDefaultUnit: true,
            defaultUnit: _unit,
            patchDefaultKgPerBag:
                _unit == 'bag' && kgParsed != null && kgParsed > 0,
            defaultKgPerBag: kgParsed,
            patchDefaultItemsPerBox: _unit == 'box',
            defaultItemsPerBox: _unit == 'box' ? 1.0 : null,
          );
      ref.invalidate(catalogItemDetailProvider(catalogId));
      invalidateCatalogItemSaveSurfaces(ref, itemId: catalogId);
      ref.invalidate(catalogItemsListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) {
        showTopSnack(
          context,
          e.response?.data?.toString() ?? 'Could not save unit. Try again.',
          isError: true,
        );
        setState(() => _saving = false);
      }
    } catch (_) {
      if (mounted) {
        showTopSnack(context, 'Could not save unit. Try again.', isError: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set stock unit',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.issue.itemName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.issue.detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Stock tracked in',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in _units)
                FilterChip(
                  label: Text(u),
                  selected: _unit == u,
                  onSelected: _saving
                      ? null
                      : (sel) {
                          if (!sel) return;
                          setState(() {
                            _unit = u;
                            _kgError = null;
                          });
                        },
                ),
            ],
          ),
          if (_unit == 'bag') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _kgCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Kg per bag *',
                hintText: 'e.g. 50',
                errorText: _kgError,
              ),
              onChanged: (_) {
                if (_kgError != null) setState(() => _kgError = null);
              },
            ),
            const SizedBox(height: 8),
            BagDefaultUnitHint(
              kgAlreadySet: () {
                final v = parseOptionalKgPerBag(_kgCtrl.text);
                return v != null && v > 0;
              }(),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save & continue'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
