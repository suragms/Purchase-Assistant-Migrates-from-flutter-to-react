import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/trade_purchases_provider.dart';
import '../../../../core/utils/item_code_format.dart';
import '../../../../core/widgets/form_field_scroll.dart';
import '../../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../../shared/widgets/search_picker_sheet.dart';

/// Full-screen / sheet body for editing catalog item defaults (name, unit, costs).
class CatalogItemDefaultsEditForm extends StatefulWidget {
  const CatalogItemDefaultsEditForm({
    super.key,
    required this.pickerContext,
    required this.nameCtrl,
    required this.codeCtrl,
    required this.hsnCtrl,
    required this.taxCtrl,
    required this.kgCtrl,
    required this.ipbCtrl,
    required this.wptCtrl,
    required this.landCtrl,
    required this.sellCtrl,
    required this.initialUnit,
    this.scrollController,
    this.showHeader = false,
    this.openingStockLabel,
    this.canSetOpeningStock = false,
    this.onSetOpeningStock,
  });

  final BuildContext pickerContext;
  final TextEditingController nameCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController taxCtrl;
  final TextEditingController kgCtrl;
  final TextEditingController ipbCtrl;
  final TextEditingController wptCtrl;
  final TextEditingController landCtrl;
  final TextEditingController sellCtrl;
  final String? initialUnit;
  final ScrollController? scrollController;
  final bool showHeader;
  /// e.g. "0 KG" or "120 KG · set 3d ago"
  final String? openingStockLabel;
  final bool canSetOpeningStock;
  final VoidCallback? onSetOpeningStock;

  @override
  State<CatalogItemDefaultsEditForm> createState() =>
      CatalogItemDefaultsEditFormState();
}

class CatalogItemDefaultsEditFormState
    extends State<CatalogItemDefaultsEditForm> {
  late String? _unit;
  late final FocusNode _nameFocus;
  late final FocusNode _codeFocus;
  late final FocusNode _hsnFocus;
  late final FocusNode _taxFocus;
  late final FocusNode _kgFocus;
  late final FocusNode _ipbFocus;
  late final FocusNode _wptFocus;
  late final FocusNode _landFocus;
  late final FocusNode _sellFocus;

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
    _nameFocus = FocusNode();
    _codeFocus = FocusNode();
    _hsnFocus = FocusNode();
    _taxFocus = FocusNode();
    _kgFocus = FocusNode();
    _ipbFocus = FocusNode();
    _wptFocus = FocusNode();
    _landFocus = FocusNode();
    _sellFocus = FocusNode();
    for (final f in [
      _nameFocus,
      _codeFocus,
      _hsnFocus,
      _taxFocus,
      _kgFocus,
      _ipbFocus,
      _wptFocus,
      _landFocus,
      _sellFocus,
    ]) {
      bindFocusNodeScrollIntoView(f);
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _codeFocus.dispose();
    _hsnFocus.dispose();
    _taxFocus.dispose();
    _kgFocus.dispose();
    _ipbFocus.dispose();
    _wptFocus.dispose();
    _landFocus.dispose();
    _sellFocus.dispose();
    super.dispose();
  }

  bool get _showKgPerBag =>
      _unit == 'bag' ||
      parseOptionalKgPerBag(widget.kgCtrl.text) != null;

  @override
  Widget build(BuildContext context) {
    final sp =
        formFieldScrollPaddingForContext(context, reserveBelowField: 220);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (widget.showHeader) ...[
          Text(
            'Item identity, unit defaults, and pricing.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
        ],
        _sectionTitle(context, 'Item identity'),
        TextField(
          controller: widget.nameCtrl,
          focusNode: _nameFocus,
          scrollPadding: sp,
          decoration: const InputDecoration(labelText: 'Name *'),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.codeCtrl,
          focusNode: _codeFocus,
          scrollPadding: sp,
          inputFormatters: [ItemCodeInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Item code',
            hintText: 'RICE-PONNI-50KG',
            helperText: 'Shelf label & reports — A-Z, 0-9, hyphen',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.hsnCtrl,
          focusNode: _hsnFocus,
          scrollPadding: sp,
          decoration: const InputDecoration(labelText: 'HSN code'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.taxCtrl,
          focusNode: _taxFocus,
          scrollPadding: sp,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tax %',
            hintText: 'e.g. 5',
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Unit & packaging'),
        Text(
          'Default stock unit',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () async {
            const none = '__unit_none__';
            final id = await showSearchPickerSheet<String>(
              context: widget.pickerContext,
              title: 'Default unit',
              rows: const [
                SearchPickerRow(value: none, title: '— (unspecified)'),
                SearchPickerRow(value: 'kg', title: 'kg'),
                SearchPickerRow(value: 'bag', title: 'bag'),
                SearchPickerRow(value: 'box', title: 'box'),
                SearchPickerRow(value: 'tin', title: 'tin'),
                SearchPickerRow(value: 'piece', title: 'piece'),
              ],
              selectedValue: _unit ?? none,
            );
            if (!mounted) return;
            if (id != null) {
              setState(() => _unit = id == none ? null : id);
            }
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_unit == null ? '— (unspecified)' : '$_unit'),
          ),
        ),
        if (_showKgPerBag) ...[
          const SizedBox(height: 12),
          TextField(
            controller: widget.kgCtrl,
            focusNode: _kgFocus,
            scrollPadding: sp,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _unit == 'bag'
                  ? 'Kg per bag *'
                  : 'Kg per bag (optional)',
              hintText: 'e.g. 50',
              helperText: _unit == 'bag'
                  ? 'Required when stock unit is bag'
                  : 'Set unit to bag if this item is stocked in bags',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_unit == 'bag') ...[
            const SizedBox(height: 8),
            BagDefaultUnitHint(
              kgAlreadySet: () {
                final v = parseOptionalKgPerBag(widget.kgCtrl.text);
                return v != null && v > 0;
              }(),
            ),
          ],
        ],
        if (_unit == 'box') ...[
          const SizedBox(height: 12),
          TextField(
            controller: widget.ipbCtrl,
            focusNode: _ipbFocus,
            scrollPadding: sp,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Items per box *',
              hintText: 'How many pieces per box',
            ),
          ),
        ],
        if (_unit == 'tin') ...[
          const SizedBox(height: 12),
          TextField(
            controller: widget.wptCtrl,
            focusNode: _wptFocus,
            scrollPadding: sp,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Liters / weight per tin',
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle(context, 'Default pricing'),
        TextField(
          controller: widget.landCtrl,
          focusNode: _landFocus,
          scrollPadding: sp,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Default landing (₹)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.sellCtrl,
          focusNode: _sellFocus,
          scrollPadding: sp,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Default selling (₹)',
          ),
        ),
        if (widget.openingStockLabel != null) ...[
          const SizedBox(height: 16),
          _sectionTitle(context, 'Opening stock (system baseline)'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.openingStockLabel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.canSetOpeningStock
                      ? 'Opening + committed purchases = system total on item page.'
                      : 'Only owner/admin can set opening stock. Staff use Update physical.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.canSetOpeningStock &&
                    widget.onSetOpeningStock != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onSetOpeningStock,
                      child: const Text('Set opening stock'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  String? get selectedUnit => _unit;
}

/// Persists catalog defaults from controllers. Returns true on success.
Future<bool> saveCatalogItemDefaults({
  required WidgetRef ref,
  required String itemId,
  required String? unit,
  required TextEditingController nameCtrl,
  required TextEditingController codeCtrl,
  required TextEditingController hsnCtrl,
  required TextEditingController taxCtrl,
  required TextEditingController kgCtrl,
  required TextEditingController ipbCtrl,
  required TextEditingController wptCtrl,
  required TextEditingController landCtrl,
  required TextEditingController sellCtrl,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;

  final codeRaw = normalizeItemCode(codeCtrl.text);
  if (codeRaw.isNotEmpty && !isValidItemCode(codeRaw)) {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      error: 'Use A-Z, 0-9, hyphen, underscore only for item code',
    );
  }

  final kgParsed = unit == 'bag' ? parseOptionalKgPerBag(kgCtrl.text) : null;
  if (unit == 'bag' && (kgParsed == null || kgParsed <= 0)) {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      error: 'Kg per bag is required when unit is bag',
    );
  }

  final tax = double.tryParse(taxCtrl.text.trim());
  final ipb = double.tryParse(ipbCtrl.text.trim());
  final wpt = double.tryParse(wptCtrl.text.trim());
  final land = double.tryParse(landCtrl.text.trim());
  final sell = double.tryParse(sellCtrl.text.trim());
  try {
    await ref.read(hexaApiProvider).updateCatalogItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
          name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          itemCode: codeRaw.isEmpty ? '' : codeRaw,
          hsnCode: hsnCtrl.text.trim().isEmpty ? null : hsnCtrl.text.trim(),
          taxPercent: tax,
          defaultLandingCost: land,
          defaultSellingCost: sell,
          includeDefaultUnit: true,
          defaultUnit: unit,
          patchDefaultKgPerBag: unit == 'bag',
          defaultKgPerBag: kgParsed,
          patchDefaultItemsPerBox: unit == 'box',
          defaultItemsPerBox: ipb,
          patchDefaultWeightPerTin: unit == 'tin',
          defaultWeightPerTin: wpt,
        );
    ref.invalidate(catalogItemDetailProvider(itemId));
    ref.invalidate(tradePurchasesCatalogIntelProvider);
    invalidatePurchaseWorkspace(ref);
    return true;
  } on DioException {
    rethrow;
  }
}
