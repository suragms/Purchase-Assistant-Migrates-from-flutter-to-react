import 'dart:async';
import 'purchase_sheet_ui_helpers.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/router/navigation_ext.dart';
import '../../../../core/calc_engine.dart';
import '../../../../core/pricing/tax_mode.dart';
import '../../../../core/widgets/form_field_scroll.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../../core/units/resolved_item_unit_context.dart';
import '../../../../core/utils/line_display.dart';
import '../../../../core/unit_engine/purchase_line_unit_guard.dart';
import '../../../../core/utils/unit_classifier.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../../../shared/widgets/keyboard_safe_form_viewport.dart';
import 'item_entry/item_entry_minimal_form.dart';
import 'item_entry/item_entry_payload.dart';
import 'party_inline_suggest_field.dart';
import 'purchase_item_entry_sections.dart';
import '../../pricing/purchase_tax_prefs.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../state/purchase_smart_defaults.dart';

String _stripKgSuffixForCatalogDisplay(String name) => name
    .replaceAll(RegExp(r'\s*\d+(\.\d+)?\s*KG\s*$', caseSensitive: false), '')
    .trim();

mixin PurchaseItemEntrySheetStateMixin {
  String _fmtQty(double d) => formatStockQtyNumber(d);

  String _fmtMoney(double d) {
    if (d <= 0) return '';
    return d.toStringAsFixed(2);
  }

}

/// Persist [default_kg_per_bag] (+ optional rename) for catalog items used as bags.
typedef PersistCatalogBagWeight = Future<void> Function({
  required String catalogItemId,
  required String newName,
  required double defaultKgPerBag,
});

/// One purchase line: catalog search, qty/unit, landing, selling, optional
/// tax/discount (per kg for bag with a catalog kg snapshot, else per unit).
class PurchaseItemEntrySheet extends ConsumerStatefulWidget {
  const PurchaseItemEntrySheet({
    super.key,
    required this.catalog,
    this.initial,
    required this.isEdit,
    required this.onCommitted,

    /// When set, each catalog pick refetches the item so HSN/tax/kg match the server
    /// (list payloads may be incomplete). Failures keep list-row data only.
    this.resolveCatalogItem,
    this.resolveLastDefaults,
    this.onDefaultsResolved,

    /// Full-screen [Scaffold] (ENTRY Prompt 1) instead of a bottom sheet.
    this.fullPage = false,

    /// When true, line payload omits freight / delivered / billty / line discount (purchase header carries these).
    this.omitLineFreightDeliveredBilltyDiscount = false,

    /// Optional: push catalog add-item route; caller invalidates catalog + returns `{id,name}`.
    this.navigateCatalogQuickAddItem,

    /// When set, user can save missing kg/bag to the server from a blocking sheet.
    this.persistCatalogBagWeight,
    this.preferredSupplierId,
    this.priorityCatalogItemIds = const [],

    /// Reserved for future line-level prefs; rates are always entered **before** GST (Tax % applies on top).
    this.gstPrefs,
  });

  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic>? initial;
  final bool isEdit;
  final void Function(Map<String, dynamic> line) onCommitted;
  final Future<Map<String, dynamic>> Function(String catalogItemId)?
      resolveCatalogItem;
  final Future<Map<String, dynamic>> Function(String catalogItemId)?
      resolveLastDefaults;
  final void Function(Map<String, dynamic> defaults)? onDefaultsResolved;
  final bool fullPage;
  final bool omitLineFreightDeliveredBilltyDiscount;
  final Future<Map<String, dynamic>?> Function()? navigateCatalogQuickAddItem;
  final PersistCatalogBagWeight? persistCatalogBagWeight;
  final String? preferredSupplierId;
  final List<String> priorityCatalogItemIds;
  final SharedPreferences? gstPrefs;

  @override
  ConsumerState<PurchaseItemEntrySheet> createState() =>
      _PurchaseItemEntrySheetState();
}

class _PurchaseItemEntrySheetState extends ConsumerState<PurchaseItemEntrySheet>
    with PurchaseItemEntrySheetStateMixin {
  // Master rebuild default wholesale mode: inventory is count-only for BOX/TIN.
  // Advanced weight/item tracking for BOX/TIN is intentionally disabled for now.
  static const bool _advancedInventoryEnabled = false;
  final _scrollController = ScrollController();
  final _itemKey = GlobalKey();
  final _qtyKey = GlobalKey();
  final _unitKey = GlobalKey();
  final _landingKey = GlobalKey();
  final _sellingKey = GlobalKey();
  final _kgPerBagKey = GlobalKey();
  final _taxKey = GlobalKey();

  /// Discount / tax % / freight / notes —” expanded when user opens or when save needs Tax %.
  bool _moreSectionExpanded = false;

  /// Primary UX: [TaxMode.none] forces `tax_percent = 0` on save; other modes use item/catalog %.
  TaxMode _taxMode = TaxMode.exclusive;
  late final ValueNotifier<TaxMode> _taxModeNotifier;

  /// Extra bottom inset so fields clear pinned preview + IME when scrolling into view.
  static const double _kPinnedPreviewReserve = 310;

  bool _commitInFlight = false;

  final _itemCtrl = TextEditingController();
  final _itemFocus = FocusNode();
  final _qtyFocus = FocusNode();
  final _landingFocus = FocusNode();
  final _sellingFocus = FocusNode();
  final _kgManualFocus = FocusNode();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'kg');
  final _landingCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();

  /// Manual kg per bag (when no catalog row or catalog row has no default_kg_per_bag).
  final _kgPerBagCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  final _deliveredCtrl = TextEditingController();
  final _billtyCtrl = TextEditingController();
  final _itemsPerBoxCtrl = TextEditingController();
  final _weightPerItemCtrl = TextEditingController();
  final _kgPerBoxCtrl = TextEditingController();
  final _weightPerTinCtrl = TextEditingController();
  final _lineNotesCtrl = TextEditingController();

  /// Persisted catalog row id for the line (`catalog_item_id` on save).
  String? _selectedCatalogItemId;

  /// When true: bag with kg snapshot —” user enters landing & selling per kg.
  bool _weightPricing = false;

  /// kg per bag (from `default_kg_per_bag` or saved line).
  double? _kgPerUnit;
  String _freightType = 'separate';
  bool _boxFixedWeight = true;

  /// For bag lines: allow qty entry as **bags** or **kg** (converted to bags on save).
  String _qtyEntryMode = 'bags'; // 'bags' | 'kg'

  /// For weight-bag ₹/kg economics: text fields hold **per kg** vs **per bag** amounts.
  bool _rateFieldsPerKg = true;

  String? _errItem;
  String? _errQty;
  String? _errUnit;
  String? _errLanding;
  String? _errSelling;
  String? _errKgPerBag;
  String? _errHsn;
  String? _hsnCode;
  String? _itemCode;
  final Map<String, Map<String, dynamic>> _catalogFetchById = {};

  /// Non-null after [resolveLastDefaults] applied meaningful trade history.
  String? _lastPurchaseAutofillHint;

  /// Ignore stale default fetches when the user selects another catalog row mid-flight.
  int _catalogPickSeq = 0;

  /// True while a suggestion pick mutates `_itemCtrl` + `_selectedCatalogItemId`; skips
  /// the label-vs-row unlink in `_onItemTextChanged` for that microtask window.
  bool _suppressCatalogTextUnlink = false;
  Timer? _defaultsDebounceTimer;

  bool _keyboardVisible = false;
  late final Listenable _lineTotalsListenable;

  /// Memoized catalog rows as [InlineSearchItem] (rebuilt when [widget.catalog] changes).
  List<InlineSearchItem> _catalogSearchItems = const [];

  /// Short hint driven by [_activeClassification()] after catalog/name changes.
  String? _unitDetectHint;

  /// Snapshot of text fields after init / reset —” for unsaved-change guard (full-page).
  Map<String, String>? _fieldBaseline;

  /// Indian grouping for weight line (display only).
  static final NumberFormat _inQtyWtFmt = NumberFormat('#,##,##0.###', 'en_IN');

  void _onItemTextChanged() {
    if (!mounted) return;
    if (_suppressCatalogTextUnlink) return;
    // If the user edits the typed label away from the selected catalog row,
    // unlink automatically so we don't persist a stale `catalog_item_id`.
    // Without this, selecting "Rice" then typing "Rice123" would silently save
    // the line against the Rice catalog id.
    if (_selectedCatalogItemId != null && _selectedCatalogItemId!.isNotEmpty) {
      if (!_itemTextMatchesSelectedCatalog(_itemCtrl.text)) {
        setState(() {
          _catalogPickSeq++;
          _selectedCatalogItemId = null;
          _lastPurchaseAutofillHint = null;
          _unitDetectHint = null;
          _errItem = null;
          _hsnCode = null;
          _itemCode = null;
        });
        return;
      }
    }
    _maybeAutoSeedKgFromName();
    if (_errItem != null) setState(() => _errItem = null);
  }

  /// [Bug 2 fix] When unit is `bag` and the item label contains "NN KG"
  /// (e.g. "SUGAR 50 KG"), auto-populate `_kgPerUnit` and the kg-per-bag input
  /// so 100 bags × 50kg = 5000 kg renders correctly without a manual entry.
  /// Catalog kg/bag (when present) wins over name parsing.
  void _maybeAutoSeedKgFromName() {
    if (_kgPerUnit != null && _kgPerUnit! > 0) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    if (_hasCatalogKg()) return;
    final c = _activeClassification();
    final kn = c.kgFromName;
    if (kn == null || kn <= 0) return;
    setState(() {
      _kgPerUnit = kn;
      _weightPricing = true;
      _kgPerBagCtrl.text = _fmtQty(kn);
    });
  }

  void _onKgPerBagChanged() {
    final v = _parseD(_kgPerBagCtrl.text);
    if (!mounted) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    final bagFamily = u == 'bag' || u == 'sack'; // legacy sack treated as bag
    setState(() {
      _kgPerUnit = (v != null && v > 0) ? v : null;
      _weightPricing = bagFamily && _kgPerUnit != null && _kgPerUnit! > 0;
      if (_errKgPerBag != null) _errKgPerBag = null;
    });
  }

  void _maybeCoerceQtyModeForUnit() {
    if (!_isBagFamilyUnit()) {
      if (_qtyEntryMode != 'bags') {
        setState(() => _qtyEntryMode = 'bags');
      }
      return;
    }
    final k = _kgPer();
    if (k == null || k <= 0) {
      if (_qtyEntryMode != 'bags') {
        setState(() => _qtyEntryMode = 'bags');
      }
    }
  }

  void _schedulePreviewRebuild() {
    if (!mounted) return;
    setState(() {});
  }

  void _onFocusChange() {
    // Proactively check FocusScope for any focused descendant.
    final hasFocus = FocusScope.of(context).focusedChild != null;
    if (hasFocus != _keyboardVisible) {
      if (mounted) setState(() => _keyboardVisible = hasFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    _itemFocus.addListener(_onFocusChange);
    _qtyFocus.addListener(_onFocusChange);
    _landingFocus.addListener(_onFocusChange);
    _sellingFocus.addListener(_onFocusChange);
    _kgManualFocus.addListener(_onFocusChange);
    _onFocusChange(); // Initial check
    _itemCtrl.addListener(_onItemTextChanged);
    _kgPerBagCtrl.addListener(_onKgPerBagChanged);
    final init = widget.initial;
    if (init != null) {
      _itemCtrl.text = init['item_name']?.toString() ?? '';
      _selectedCatalogItemId = init['catalog_item_id']?.toString();
      final qVal = coerceToDoubleNullable(init['qty']);
      if (qVal != null) {
        _qtyCtrl.text = (qVal - qVal.roundToDouble()).abs() < 1e-9
            ? qVal.round().toString()
            : qVal.toString();
      } else {
        _qtyCtrl.text = '';
      }
      _unitCtrl.text = init['unit']?.toString() ?? 'kg';
      _qtyEntryMode = 'bags';

      final kpu = coerceToDoubleNullable(
          init['kg_per_unit'] ?? init['weight_per_unit']);
      final lck = coerceToDoubleNullable(init['landing_cost_per_kg']);
      if (kpu != null && kpu > 0) {
        _weightPricing = true;
        _kgPerUnit = kpu;
        _kgPerBagCtrl.text = _fmtQty(kpu);
        if (lck != null && lck > 0) {
          _landingCtrl.text = lck.toStringAsFixed(2);
        } else {
          final lc = coerceToDoubleNullable(
              init['landing_cost'] ?? init['purchase_rate']);
          if (lc != null && lc > 0) {
            _landingCtrl.text = (lc / kpu).toStringAsFixed(2);
          } else {
            _landingCtrl.text = '';
          }
        }
        final sc = coerceToDoubleNullable(
            init['selling_cost'] ?? init['selling_rate']);
        if (sc != null && sc > 0) {
          _sellingCtrl.text = (sc / kpu).toStringAsFixed(2);
        } else {
          _sellingCtrl.text = '';
        }
      } else {
        _weightPricing = false;
        _kgPerUnit = null;
        final r = coerceToDoubleNullable(
            init['landing_cost'] ?? init['purchase_rate']);
        _landingCtrl.text = r != null && r > 0 ? r.toStringAsFixed(2) : '';
        final s = coerceToDoubleNullable(
            init['selling_cost'] ?? init['selling_rate']);
        if (s != null && s > 0) {
          _sellingCtrl.text = s.toStringAsFixed(2);
        } else {
          _sellingCtrl.text = '';
        }
      }

      final d = coerceToDoubleNullable(init['discount']);
      _discCtrl.text = d != null && d > 0 ? d.toString() : '';
      final parsedMode = taxModeFromWire(init['tax_mode']?.toString());
      if (parsedMode != null) {
        _taxMode = parsedMode;
      } else {
        final t0 = coerceToDoubleNullable(init['tax_percent']);
        _taxMode = (t0 != null && t0 > 0) ? TaxMode.exclusive : TaxMode.none;
      }
      final t = coerceToDoubleNullable(init['tax_percent']);
      _taxCtrl.text = t != null && t > 0 ? t.toString() : '';
      final hsn = init['hsn_code']?.toString().trim() ?? '';
      _hsnCode = hsn.isEmpty ? null : hsn;
      final ic = init['item_code']?.toString().trim() ?? '';
      _itemCode = ic.isEmpty ? null : ic;
      _lineNotesCtrl.text = init['description']?.toString() ?? '';
      final ft = init['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') _freightType = ft!;
      _freightCtrl.text =
          _fmtInput(init['freight_value'] ?? init['freight_amount'], 2);
      _deliveredCtrl.text = _fmtInput(init['delivered_rate'], 2);
      _billtyCtrl.text = _fmtInput(init['billty_rate'], 2);
      _itemsPerBoxCtrl.text = _fmtInput(init['items_per_box'], 3, trim: true);
      _weightPerItemCtrl.text =
          _fmtInput(init['weight_per_item'], 3, trim: true);
      _kgPerBoxCtrl.text = _fmtInput(init['kg_per_box'], 3, trim: true);
      _weightPerTinCtrl.text = _fmtInput(init['weight_per_tin'], 3, trim: true);
      _boxFixedWeight = (init['box_mode']?.toString() != 'items_per_box');
    }
    _syncKgStateFromCatalogRow();
    _taxModeNotifier = ValueNotifier(_taxMode);
    _lineTotalsListenable = Listenable.merge([
      _qtyCtrl,
      _unitCtrl,
      _landingCtrl,
      _discCtrl,
      _taxCtrl,
      _sellingCtrl,
      _freightCtrl,
      _deliveredCtrl,
      _billtyCtrl,
      _itemsPerBoxCtrl,
      _weightPerItemCtrl,
      _kgPerBoxCtrl,
      _weightPerTinCtrl,
      _kgPerBagCtrl,
      _taxModeNotifier,
    ]);
    _rebuildCatalogSearchItems();
    _storeFieldBaseline();
    final cid = (_selectedCatalogItemId ?? '').trim();
    final itemNm = _itemCtrl.text.trim();
    if (cid.isEmpty && itemNm.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).requestFocus(_itemFocus);
      });
    }
    _qtyFocus.addListener(_onQtyFocusScroll);
    _landingFocus.addListener(_onLandingFocusScroll);
    _sellingFocus.addListener(_onSellingFocusScroll);
    _kgManualFocus.addListener(_onKgManualFocusScroll);
    _itemFocus.addListener(_onItemFocusScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.initial != null || !mounted) return;
      final p = widget.gstPrefs ?? await SharedPreferences.getInstance();
      if (!mounted) return;
      final saved = PurchaseLineTaxModePrefs.read(p);
      setState(() => _taxMode = saved);
      _taxModeNotifier.value = saved;
    });
  }

  void _syncKgStateFromCatalogRow() {
    if (_selectedCatalogItemId == null || _selectedCatalogItemId!.isEmpty) {
      return;
    }
    if (_kgPerUnit != null && _kgPerUnit! > 0) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    final r = _catalogRowById(_selectedCatalogItemId!);
    if (r == null) return;
    for (final key in <String>[
      'default_kg_per_bag',
      'kg_per_bag',
      'kg_per_unit'
    ]) {
      final v = r[key];
      if (v is num && v > 0) {
        _kgPerUnit = v.toDouble();
        _weightPricing = true;
        return;
      }
    }
  }

  @override
  void dispose() {
    _itemFocus.removeListener(_onItemFocusScroll);
    _qtyFocus.removeListener(_onQtyFocusScroll);
    _landingFocus.removeListener(_onLandingFocusScroll);
    _sellingFocus.removeListener(_onSellingFocusScroll);
    _kgManualFocus.removeListener(_onKgManualFocusScroll);
    _itemCtrl.removeListener(_onItemTextChanged);
    _kgPerBagCtrl.removeListener(_onKgPerBagChanged);
    _taxModeNotifier.dispose();
    _defaultsDebounceTimer?.cancel();
    _scrollController.dispose();
    _itemCtrl.dispose();
    _itemFocus.dispose();
    _qtyFocus.dispose();
    _landingFocus.dispose();
    _sellingFocus.dispose();
    _kgManualFocus.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _landingCtrl.dispose();
    _discCtrl.dispose();
    _taxCtrl.dispose();
    _sellingCtrl.dispose();
    _kgPerBagCtrl.dispose();
    _freightCtrl.dispose();
    _deliveredCtrl.dispose();
    _billtyCtrl.dispose();
    _itemsPerBoxCtrl.dispose();
    _weightPerItemCtrl.dispose();
    _kgPerBoxCtrl.dispose();
    _weightPerTinCtrl.dispose();
    _lineNotesCtrl.dispose();
    super.dispose();
  }

  String _fmtInput(Object? value, int scale, {bool trim = false}) {
    if (value == null) return '';
    try {
      final d = StrictDecimal.fromObject(value);
      if (d.isZero) return '';
      return d.format(scale, trim: trim);
    } on FormatException {
      return '';
    }
  }

  Map<String, dynamic>? _catalogRowById(String id) {
    final cached = _catalogFetchById[id];
    if (cached != null) return cached;
    for (final m in widget.catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  Map<String, dynamic>? _rowForClassification() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return null;
    return _catalogRowById(id);
  }

  double? _catalogKpb(Map<String, dynamic>? row) {
    if (row == null) return null;
    for (final key in <String>[
      'default_kg_per_bag',
      'kg_per_bag',
      'kg_per_unit',
    ]) {
      final v = row[key];
      if (v is num && v > 0) return v.toDouble();
    }
    return null;
  }

  /// Current label + catalog + wired unit â†’ [UnitClassification] for UI/validation/math.
  UnitClassification _activeClassification() {
    final row = _rowForClassification();
    return UnitClassifier.classify(
      itemName: _itemCtrl.text.trim(),
      lineUnit: _unitCtrl.text,
      catalogDefaultUnit: row?['default_unit']?.toString(),
      catalogDefaultKgPerBag: _catalogKpb(row),
      categoryName:
          row?['category_name']?.toString() ?? row?['category']?.toString(),
      subcategoryName: row?['subcategory_name']?.toString() ??
          row?['subcategory']?.toString(),
    );
  }

  ResolvedItemUnitContext _resolvedUnitContext() {
    final row = _rowForClassification();
    return resolveItemUnitContext(
      itemName: _itemCtrl.text.trim(),
      currentLineUnit: _unitCtrl.text,
      catalogRow: row,
      fallbackClassification: _activeClassification(),
    );
  }

  String _wireUnitFromClassification({
    required UnitClassification c,
    required Map<String, dynamic>? row,
    required double? kpbD,
    required String displayName,
  }) {
    final resolved = resolveItemUnitContext(
      itemName: displayName,
      currentLineUnit: row?['default_purchase_unit']?.toString() ??
          row?['default_unit']?.toString() ??
          '',
      catalogRow: row,
      fallbackClassification: c,
    );
    if (resolved.unitConfidence >= 60 &&
        const {'bag', 'box', 'tin', 'kg', 'pcs'}
            .contains(resolved.sellingUnit)) {
      return resolved.sellingUnit == 'pcs' ? 'pcs' : resolved.sellingUnit;
    }
    final dn = displayName.toUpperCase();
    switch (c.type) {
      case UnitType.weightBag:
        if (row == null) return 'bag';
        final du = row['default_unit']?.toString().trim().toLowerCase();
        if (du == 'sack') return 'bag';
        return 'bag';
      case UnitType.multiPackBox:
        return 'box';
      case UnitType.singlePack:
        if (dn.contains('TIN')) return 'tin';
        if (dn.contains('BOX') || dn.contains('CTN') || dn.contains('CARTON')) {
          return 'box';
        }
        if (row == null) return 'kg';
        return _lineUnitForCatalog(row, kpbD: kpbD);
    }
  }

  String? _hintFromClassification(UnitClassification c, String wireUnit) {
    switch (c.type) {
      case UnitType.weightBag:
        if (c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg bag';
        }
        return 'Classified: weight bag';
      case UnitType.multiPackBox:
        return 'Classified: items/box';
      case UnitType.singlePack:
        if (wireUnit == 'box' && c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg box';
        }
        if (wireUnit == 'tin' && c.kgFromName != null && c.kgFromName! > 0) {
          return 'Classified: ${_fmtQty(c.kgFromName!)} kg tin';
        }
        return null;
    }
  }

  void _adjustBoxFixedForClassification(UnitClassification c) {
    if (!_lineUnitIsBox(_unitCtrl.text)) return;
    if (c.type == UnitType.multiPackBox) _boxFixedWeight = false;
    if (c.type == UnitType.singlePack) _boxFixedWeight = true;
  }

  String? _hsnFromRow(Map<String, dynamic> row) {
    final a = row['hsn_code']?.toString().trim() ?? '';
    if (a.isNotEmpty) return a;
    final b = row['hsn']?.toString().trim() ?? '';
    return b.isEmpty ? null : b;
  }

  String? _itemCodeFromRow(Map<String, dynamic> row) {
    final a = row['item_code']?.toString().trim() ?? '';
    return a.isEmpty ? null : a;
  }

  static bool _lineUnitIsBox(String? u) =>
      (u ?? '').trim().toLowerCase() == 'box';
  static bool _lineUnitIsTin(String? u) =>
      (u ?? '').trim().toLowerCase() == 'tin';

  static bool _isWeightUnit(String? u) {
    final x = (u ?? '').trim().toLowerCase();
    // Back-compat: treat legacy `sack` as canonical `bag`.
    return x == 'bag' || x == 'sack';
  }

  // Master rebuild: only kg / bag / box / tin are allowed for new lines.
  // `sack` and `piece` removed from the dropdown; legacy rows still display
  // (sack normalized to bag for back-compat, see _onUnitDropdownChanged).
  static const _unitDropdownBaseChoices = <String>[
    'kg',
    'bag',
    'box',
    'tin',
  ];

  List<String> _suggestedUnitChoices() {
    final row = _selectedCatalogItemId != null
        ? _catalogRowById(_selectedCatalogItemId!)
        : null;
    final du = (row?['default_unit']?.toString() ?? '').trim().toLowerCase();
    final c = _activeClassification();
    final resolved = _resolvedUnitContext();

    // Default: keep the list short to reduce mis-taps.
    // Always include the currently selected unit (even if it isn't in the base list).
    final out = <String>{};

    if (resolved.unitConfidence >= 60) {
      out.add(resolved.sellingUnit);
      if (resolved.sellingUnit == 'bag') out.add('kg');
      if (resolved.sellingUnit == 'kg') out.add('bag');
      if (resolved.sellingUnit == 'box' || resolved.sellingUnit == 'tin') {
        out.add(resolved.sellingUnit);
      }
    }

    if (du == 'bag' || du == 'sack') {
      out.addAll(const {'bag', 'kg'});
    } else if (du == 'box') {
      out.addAll(const {'box', 'kg'});
    } else if (du == 'tin') {
      out.addAll(const {'tin', 'kg'});
    } else if (du == 'kg') {
      out.addAll(const {'kg', 'bag'});
    }

    if (c.type == UnitType.weightBag) {
      out.addAll(const {'bag', 'kg'});
    } else if (c.type == UnitType.multiPackBox) {
      out.addAll(const {'box', 'kg'});
    } else if (c.type == UnitType.singlePack) {
      out.addAll(const {'kg'});
      if (_lineUnitIsBox(_unitCtrl.text)) out.add('box');
      if (_lineUnitIsTin(_unitCtrl.text)) out.add('tin');
    }

    // Fallback when we couldn't infer anything.
    if (out.isEmpty) {
      out.addAll(_unitDropdownBaseChoices);
    }

    final current = normalizeUnitToken(_unitCtrl.text);
    if (current.isNotEmpty && current != 'unit') {
      out.add(current == 'qtl' ? 'quintal' : current);
    }

    // Return ordered by our base list first, then anything else.
    final ordered = <String>[
      for (final u in _unitDropdownBaseChoices)
        if (out.contains(u)) u,
      for (final u in out)
        if (!_unitDropdownBaseChoices.contains(u)) u,
    ];
    return ordered;
  }

  String _unitDropdownValue() {
    var t = normalizeUnitToken(_unitCtrl.text);
    final resolved = _resolvedUnitContext();
    if ((t == 'piece' || t == 'pcs' || t == 'unit') &&
        resolved.unitConfidence >= 60 &&
        resolved.sellingUnit != 'pcs') {
      t = resolved.sellingUnit;
    }
    if (t == 'qtl') t = 'quintal';
    if (t.isNotEmpty && !_unitDropdownBaseChoices.contains(t)) return t;
    if (_unitDropdownBaseChoices.contains(t)) return t;
    return 'kg';
  }

  void _onUnitDropdownChanged(String? value) {
    if (value == null) return;
    var v = value;
    // Back-compat: normalize legacy `sack` to canonical `bag`.
    if (v.trim().toLowerCase() == 'sack') v = 'bag';
    _clearFieldErrors();
    final vLow = v.trim().toLowerCase();

    // Default wholesale mode: BOX/TIN are count-only. Clear any weight fields so
    // we never accidentally derive kg totals or show hidden inputs.
    if (!_advancedInventoryEnabled && (vLow == 'box' || vLow == 'tin')) {
      _weightPricing = false;
      _rateFieldsPerKg = false;
      _kgPerUnit = null;
      _kgPerBagCtrl.clear();
      _itemsPerBoxCtrl.clear();
      _weightPerItemCtrl.clear();
      _kgPerBoxCtrl.clear();
      _weightPerTinCtrl.clear();
      if (_qtyEntryMode != 'bags') _qtyEntryMode = 'bags';
    }
    if (!_isWeightUnit(v) && !_hasCatalogKg()) {
      _kgPerUnit = null;
      _kgPerBagCtrl.clear();
    }
    _recomputeModeFromUnitAndCatalog();
    _maybeCoerceQtyModeForUnit();
    setState(() {
      _unitCtrl.text = v;
      _adjustBoxFixedForClassification(_activeClassification());
    });
    // [Bug 2] After switching to bag, seed kg-per-bag from item name if catalog
    // didn't provide one (`SUGAR 50 KG` â†’ 50, `RICE 26 KG` â†’ 26).
    _maybeAutoSeedKgFromName();
    if ((vLow == 'bag' || vLow == 'sack') &&
        widget.persistCatalogBagWeight != null &&
        (_kgPer() == null || _kgPer()! <= 0)) {
      final cid = _selectedCatalogItemId?.trim();
      if (cid != null && cid.isNotEmpty) {
        final row = _catalogRowById(cid);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_offerCatalogKgPerBagSheetIfNeeded(row));
        });
      }
    }
  }

  Widget _unitDropdownField({required String? errorText}) {
    final unitMenuMax =
        math.min(260.0, MediaQuery.sizeOf(context).height * 0.38);
    final v = _unitDropdownValue();
    final ordered = _suggestedUnitChoices();
    final itemSet = <String>{...ordered, v};
    final finalOrdered = <String>[
      for (final u in ordered)
        if (itemSet.contains(u)) u,
      for (final x in itemSet)
        if (!ordered.contains(x)) x,
    ];
    return KeyedSubtree(
      key: ValueKey<String>('unit|$v'),
      child: Theme(
        data: Theme.of(context).copyWith(
          hoverColor: HexaColors.primaryLight.withValues(alpha: 0.35),
          highlightColor: HexaColors.primaryLight.withValues(alpha: 0.5),
        ),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
          initialValue: v,
          menuMaxHeight: unitMenuMax,
          dropdownColor: HexaColors.surfaceApp,
          borderRadius: BorderRadius.circular(12),
          decoration: _deco('Unit *', errorText: errorText),
          items: [
            for (final u in finalOrdered)
              DropdownMenuItem<String>(
                value: u,
                child: Text(
                  u,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: HexaColors.inputText,
                  ),
                ),
              ),
          ],
          onChanged: _onUnitDropdownChanged,
        ),
      ),
    );
  }

  /// Weight bags: ₹/kg landing × total kg purchased.
  bool get _ratesPerKgEconomics {
    return _activeClassification().type == UnitType.weightBag &&
        _kgPer() != null &&
        _kgPer()! > 0;
  }

  bool get _showPerKgLandingLabels {
    return _activeClassification().type == UnitType.weightBag;
  }

  void _onRateBasisChanged(bool wantPerKg) {
    if (wantPerKg == _rateFieldsPerKg) return;
    final k = _kgPer();
    final land = _parseD(_landingCtrl.text);
    final sell = _parseD(_sellingCtrl.text);
    setState(() {
      if (k != null && k > 0) {
        if (_rateFieldsPerKg && !wantPerKg) {
          if (land != null && land > 0) {
            _landingCtrl.text = _fmtMoney(land * k);
          }
          if (sell != null && sell > 0) {
            _sellingCtrl.text = _fmtMoney(sell * k);
          }
        } else if (!_rateFieldsPerKg && wantPerKg) {
          if (land != null && land > 0) {
            _landingCtrl.text = _fmtMoney(land / k);
          }
          if (sell != null && sell > 0) {
            _sellingCtrl.text = _fmtMoney(sell / k);
          }
        }
      }
      _rateFieldsPerKg = wantPerKg;
    });
  }

  /// Landing field interpreted as **₹/kg** for wire when [_ratesPerKgEconomics].
  double? _landingParsedAsPerKg() {
    final raw = _parseD(_landingCtrl.text);
    if (raw == null) return null;
    if (!_ratesPerKgEconomics) return raw;
    if (_rateFieldsPerKg) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  /// Selling field interpreted as **₹/kg** for wire when [_ratesPerKgEconomics].
  double? _sellingParsedAsPerKg() {
    final raw = _parseD(_sellingCtrl.text);
    if (raw == null) return null;
    if (!_ratesPerKgEconomics) return raw;
    if (_rateFieldsPerKg) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  InputDecoration _deco(
    String label, {
    String? prefixText,
    String? errorText,
  }) {
    return itemEntryFieldDecoration(
      Theme.of(context),
      label: label,
      prefixText: prefixText,
      errorText: errorText,
      fullPage: widget.fullPage,
    );
  }

  /// Rounded section shell for full-page add item only.
  Widget _fpShell(Widget child) {
    if (!widget.fullPage) return child;
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: const Color(0xFF17A8A7).withValues(alpha: 0.22),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }

  double? _parseD(String s) {
    final v = s.trim();
    if (v.isEmpty) return null;
    if (!isValidNonNegativeDecimalInput(v, maxDecimals: 3)) return null;
    try {
      return StrictDecimal.parse(v).toDouble();
    } on FormatException {
      return null;
    }
  }

  double? _numD(Object? v) {
    if (v == null) return null;
    try {
      return StrictDecimal.fromObject(v).toDouble();
    } on FormatException {
      return null;
    }
  }

  double _enteredQtyRaw() => _parseD(_qtyCtrl.text) ?? 0;

  bool _isBagFamilyUnit() {
    final u = _unitCtrl.text.trim().toLowerCase();
    return u == 'bag' || u == 'sack';
  }

  bool _bagQtyIsWhole(double bags) =>
      (bags - bags.roundToDouble()).abs() < 1e-6;

  /// Quantity interpreted as **bags** for calculations and payload.
  /// When [_qtyEntryMode] == 'kg', interpret the input as kg and convert to bags.
  double _qtyVal() {
    final raw = _enteredQtyRaw();
    if (raw <= 0) return 0;
    if (_qtyEntryMode != 'kg') return raw;
    if (!_isBagFamilyUnit()) return raw;
    final k = _kgPer();
    if (k == null || k <= 0) return raw;
    return raw / k;
  }

  /// Entered kg when in kg-mode for bag.
  double? _enteredKgForBagMode() {
    if (_qtyEntryMode != 'kg') return null;
    if (!_isBagFamilyUnit()) return null;
    final raw = _enteredQtyRaw();
    return raw > 0 ? raw : null;
  }

  TextInputFormatter _decimalFormatter(int maxDecimals) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      return isValidNonNegativeDecimalInput(
        newValue.text,
        maxDecimals: maxDecimals,
      )
          ? newValue
          : oldValue;
    });
  }

  /// kg/bag resolved to a number; single source of truth = `_kgPerUnit` (seeded
  /// from catalog row on pick OR from the manual "Kg per bag" input).
  double? _kgPer() {
    if (_kgPerUnit != null && _kgPerUnit! > 0) return _kgPerUnit;
    if (!_isBagFamilyUnit()) return null;
    final fromField = _parseD(_kgPerBagCtrl.text);
    if (fromField != null && fromField > 0) return fromField;
    // CRITICAL FIX: auto-derive from item name ("30 KG" in name = 30 kg/bag)
    final clf = _activeClassification();
    if (clf.kgFromName != null && clf.kgFromName! > 0) {
      // Sync state so future reads are consistent
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (_kgPerUnit == null || _kgPerUnit! <= 0)) {
            setState(() {
              _kgPerUnit = clf.kgFromName;
              _weightPricing = true;
              if (_kgPerBagCtrl.text.isEmpty || _parseD(_kgPerBagCtrl.text) == null) {
                _kgPerBagCtrl.text = _fmtQty(clf.kgFromName!);
              }
            });
          }
        });
      }
      return clf.kgFromName;
    }
    return null;
  }

  /// Catalog item selected AND catalog row carries kg/bag.
  bool _hasCatalogKg() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return false;
    final r = _catalogRowById(id);
    if (r == null) return false;
    for (final key in <String>[
      'default_kg_per_bag',
      'kg_per_bag',
      'kg_per_unit'
    ]) {
      final v = r[key];
      if (v is num && v > 0) return true;
    }
    return false;
  }

  double _sheetPhysicalKgTotal() {
    final c = _activeClassification();
    double? kgName = c.kgFromName;
    if (!(c.type == UnitType.singlePack &&
        ((_lineUnitIsBox(_unitCtrl.text) ||
            _lineUnitIsTin(_unitCtrl.text) ||
            (_unitCtrl.text.trim().toLowerCase() == 'kg'))))) {
      kgName = null;
    }
    return classifierLineWeightKg(
      type: c.type,
      qty: _qtyVal(),
      kgPerUnit: _kgPer(),
      kgFromName: kgName,
      itemsPerBox: _parseD(_itemsPerBoxCtrl.text),
      weightPerItem: _parseD(_weightPerItemCtrl.text),
    );
  }

  String _capitalUnitWord(String u) {
    final t = u.trim();
    if (t.isEmpty) return 'Unit';
    final lower = t.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.length > 1 ? lower.substring(1) : ''}';
  }

  String _qtyFieldLabel() {
    final resolved = _resolvedUnitContext();
    if (_qtyEntryMode != 'kg' && resolved.unitConfidence >= 60) {
      return resolved.quantityLabel;
    }
    final u = _unitCtrl.text.trim().toLowerCase();
    if (_qtyEntryMode == 'kg' && (u == 'bag' || u == 'sack')) {
      return 'Qty (kg) *';
    }
    if (u == 'bag') return 'No. of bags *';
    if (u == 'sack') return 'No. of bags *';
    if (u == 'box') return 'No. of boxes *';
    if (u == 'tin') return 'No. of tins *';
    if (u == 'kg' || u == 'kgs' || u == 'quintal' || u == 'qtl') {
      return 'Qty (kg) *';
    }
    return 'Qty *';
  }

  String _qtyAndUnitWeightSummaryLine() {
    final q = _qtyVal();
    final u = _unitCtrl.text.trim();
    if (q <= 0 || u.isEmpty) return '—”';
    final c = _activeClassification();

    if (c.type == UnitType.multiPackBox) {
      final qtyTxt = _inQtyWtFmt.format(q);
      final items = classifierTotalItems(
        type: c.type,
        qty: q,
        itemsPerBox: _parseD(_itemsPerBoxCtrl.text),
      );
      final boxWord = _capitalUnitWord('box');
      return '$qtyTxt $boxWord • ${_inQtyWtFmt.format(items)} Items';
    }

    final totalKg = _sheetPhysicalKgTotal();
    return formatLineQtyWeight(
      qty: q,
      unit: u,
      kgPerUnit: _kgPer(),
      totalWeightKg: totalKg > 1e-9 ? totalKg : null,
    );
  }

  Widget? _qtyEntryModeSegmented() {
    if (!_isBagFamilyUnit()) return null;
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    final cs = Theme.of(context).colorScheme;
    Widget chip(String label, bool sel) {
      return Expanded(
        child: Material(
          color: sel ? cs.primaryContainer : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              setState(() {
                _qtyEntryMode = label == 'Bags' ? 'bags' : 'kg';
                _errQty = null;
              });
              _schedulePreviewRebuild();
            },
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color:
                        sel ? cs.onPrimaryContainer : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          chip('Bags', _qtyEntryMode == 'bags'),
          const SizedBox(width: 8),
          chip('Kg', _qtyEntryMode == 'kg'),
        ],
      ),
    );
  }

  Widget? _kgEntryConversionHint() {
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    final enteredKg = _enteredKgForBagMode();
    if (enteredKg == null || enteredKg <= 0) return null;
    final bags = enteredKg / k;
    final theme = Theme.of(context);

    final bagsTxt = _bagQtyIsWhole(bags) ? '${bags.round()}' : _fmtQty(bags);
    final kgTxt = _inQtyWtFmt.format(enteredKg);
    final totalKgTxt = _inQtyWtFmt.format(bags * k);
    final needsWhole = !_bagQtyIsWhole(bags);

    return Material(
      color: needsWhole ? const Color(0xFFFFF7ED) : const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '$kgTxt kg â†’ $bagsTxt ${_unitCtrl.text.trim()}'
                '${needsWhole ? ' (needs whole bags)' : ''}'
                '  ·  $bagsTxt × ${_fmtQty(k)} kg/bag = $totalKgTxt kg',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: needsWhole
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF065F46),
                  height: 1.25,
                ),
              ),
            ),
            if (needsWhole) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final flo = (bags).floorToDouble();
                  final nextKg = flo * k;
                  setState(() {
                    _qtyCtrl.text = _fmtQty(nextKg);
                    _errQty = null;
                  });
                  _schedulePreviewRebuild();
                },
                child: const Text('Round down'),
              ),
              TextButton(
                onPressed: () {
                  final cei = (bags).ceilToDouble();
                  final nextKg = cei * k;
                  setState(() {
                    _qtyCtrl.text = _fmtQty(nextKg);
                    _errQty = null;
                  });
                  _schedulePreviewRebuild();
                },
                child: const Text('Round up'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Minimal line for unit-label engine (purchase/selling suffix chips).
  TradePurchaseLine _draftLineForLabelsOnly() {
    final u = _unitCtrl.text.trim();
    final unit = u.isEmpty ? 'unit' : u;
    final kpu = _kgPer();
    final lcpk = _landingParsedAsPerKg();

    if (!_showPerKgLandingLabels) {
      return TradePurchaseLine(
        id: '_',
        itemName: '',
        qty: _qtyVal(),
        unit: unit,
        landingCost: _parseD(_landingCtrl.text) ?? 0,
        kgPerUnit: kpu,
        landingCostPerKg: lcpk,
      );
    }

    final baseRc = unit_lbl.effectiveRateContextFields(
      rateContext: null,
      unit: u,
      kgPerUnit: kpu,
      landingCostPerKg: lcpk,
    );
    final altDim = _isBagFamilyUnit()
        ? 'bag'
        : (baseRc['purchase_rate_dim']?.toString() ?? 'unit');
    final purchaseDim = _rateFieldsPerKg ? 'kg' : altDim;
    final rc = Map<String, dynamic>.from(baseRc);
    rc['purchase_rate_dim'] = purchaseDim;
    rc['selling_rate_dim'] = purchaseDim;

    return TradePurchaseLine(
      id: '_',
      itemName: '',
      qty: _qtyVal(),
      unit: unit,
      landingCost: _parseD(_landingCtrl.text) ?? 0,
      kgPerUnit: kpu,
      landingCostPerKg: lcpk,
      rateContext: rc,
    );
  }

  double? _numericTaxFromCatalogRow() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return null;
    final row = _catalogRowById(id);
    if (row == null) return null;
    return _numD(row['tax_percent']);
  }

  /// Effective tax % for preview + [TradeCalcLine] math (0 when [TaxMode.none]).
  double _effectiveTaxPercentForLine() {
    if (_taxMode == TaxMode.none) return 0;
    final typed = _parseD(_taxCtrl.text);
    if (typed != null && typed > 0) return typed;
    return (_numericTaxFromCatalogRow() ?? 0).clamp(0.0, 100.0);
  }

  TradeCalcLine _currentLine() {
    final qty = _qtyVal();
    final disc = _parseD(_discCtrl.text);
    final tax = _effectiveTaxPercentForLine();
    final fv = _parseD(_freightCtrl.text);
    final dr = _parseD(_deliveredCtrl.text);
    final br = _parseD(_billtyCtrl.text);
    if (_ratesPerKgEconomics) {
      final kpu = _kgPer()!;
      final perKgIn = _landingParsedAsPerKg() ?? 0;
      final perKg = perKgIn;
      return TradeCalcLine(
        qty: qty,
        landingCost: kpu * perKg,
        kgPerUnit: kpu,
        landingCostPerKg: perKg,
        discountPercent: disc,
        taxPercent: tax,
        freightType: _freightType,
        freightValue: fv,
        deliveredRate: dr,
        billtyRate: br,
      );
    }
    final landIn = _parseD(_landingCtrl.text) ?? 0;
    final land = landIn;
    return TradeCalcLine(
      qty: qty,
      landingCost: land,
      discountPercent: disc,
      taxPercent: tax,
      freightType: _freightType,
      freightValue: fv,
      deliveredRate: dr,
      billtyRate: br,
    );
  }

  Widget? _rateEntryBasisSegmented(double? kPer, bool showPerKg) {
    if (!showPerKg || kPer == null || kPer <= 0) return null;
    final kgChip = unit_lbl.rupeePerDimChipLabel('kg');
    final altDim = _isBagFamilyUnit() ? 'bag' : 'unit';
    final altChip = unit_lbl.rupeePerDimChipLabel(altDim);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(kgChip)),
            ButtonSegment(value: false, label: Text(altChip)),
          ],
          selected: {_rateFieldsPerKg},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            _onRateBasisChanged(s.first);
          },
        ),
      ),
    );
  }

  double _profitPreview() {
    if (_qtyVal() <= 0) return 0;
    final sellIn = _ratesPerKgEconomics
        ? _sellingParsedAsPerKg()
        : _parseD(_sellingCtrl.text);
    if (sellIn == null) return 0;
    final sell = sellIn;
    final lineCharges = widget.omitLineFreightDeliveredBilltyDiscount
        ? 0.0
        : (_freightType == 'separate' ? (_parseD(_freightCtrl.text) ?? 0) : 0) +
            (_parseD(_deliveredCtrl.text) ?? 0) +
            (_parseD(_billtyCtrl.text) ?? 0);
    if (_ratesPerKgEconomics) {
      final k = _kgPer()!;
      final perKgLand = _landingParsedAsPerKg() ?? 0;
      final totalK = _qtyVal() * k;
      return ((sell - perKgLand) * totalK) - lineCharges;
    }
    final rate = _parseD(_landingCtrl.text) ?? 0;
    return ((sell - rate) * _qtyVal()) - lineCharges;
  }

  void _clearFieldErrors() {
    setState(() {
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
      _errHsn = null;
    });
  }

  void _rebuildCatalogSearchItems() {
    final pref = widget.preferredSupplierId?.trim();
    final priority = widget.priorityCatalogItemIds;
    final out = <InlineSearchItem>[];
    for (final row in widget.catalog) {
      var boost = 0;
      final rowId = row['id']?.toString() ?? '';
      if (rowId.isNotEmpty && priority.isNotEmpty) {
        final idx = priority.indexOf(rowId);
        if (idx >= 0) {
          boost += 400 - (idx * 20);
        }
      }
      if (pref != null && pref.isNotEmpty) {
        final ls = row['last_supplier_id']?.toString().trim();
        if (ls == pref) boost += 120;
        final ids = row['default_supplier_ids'];
        if (ids is List) {
          for (final e in ids) {
            if (e != null && e.toString().trim() == pref) {
              boost += 80;
              break;
            }
          }
        }
      }
      final blob = _catalogSearchBlob(row);
      final sub = _catalogSearchSuggestionSubtitle(row).trim();
      final name = row['name']?.toString() ?? '';
      out.add(
        InlineSearchItem(
          id: row['id']?.toString() ?? '',
          label: name.isEmpty ? name : _catalogSearchLabelForRow(row),
          subtitle: sub.isEmpty ? null : sub,
          searchText: blob.isEmpty ? null : blob,
          sortBoost: boost,
        ),
      );
    }
    _catalogSearchItems = out;
  }

  /// Space-joined lowercase tokens for typeahead (name + code + HSN).
  String _catalogSearchBlob(Map<String, dynamic> row) {
    final parts = <String>[
      row['name']?.toString().trim() ?? '',
      row['item_code']?.toString().trim() ?? '',
      row['hsn_code']?.toString().trim() ?? '',
      row['hsn']?.toString().trim() ?? '',
      row['category_name']?.toString().trim() ?? '',
      row['subcategory_name']?.toString().trim() ?? '',
    ].where((s) => s.isNotEmpty);
    return parts.join(' ').toLowerCase();
  }

  @override
  void didUpdateWidget(covariant PurchaseItemEntrySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog ||
        oldWidget.preferredSupplierId != widget.preferredSupplierId ||
        oldWidget.priorityCatalogItemIds != widget.priorityCatalogItemIds) {
      _rebuildCatalogSearchItems();
    }
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  EdgeInsets _textFieldScrollPadding() {
    final reserve = widget.fullPage ? _kPinnedPreviewReserve : 140.0;
    return formFieldScrollPaddingForContext(
      context,
      reserveBelowField: reserve,
    );
  }

  void _ensureFocusedFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.18,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onItemFocusScroll() {
    if (_itemFocus.hasFocus) _ensureFocusedFieldVisible();
  }

  void _onQtyFocusScroll() {
    if (_qtyFocus.hasFocus) _ensureFocusedFieldVisible();
  }

  void _onLandingFocusScroll() {
    if (_landingFocus.hasFocus) _ensureFocusedFieldVisible();
  }

  void _onSellingFocusScroll() {
    if (_sellingFocus.hasFocus) _ensureFocusedFieldVisible();
  }

  void _onKgManualFocusScroll() {
    if (_kgManualFocus.hasFocus) _ensureFocusedFieldVisible();
  }

  void _scrollToFirstBlockingError() {
    if (_errItem != null) {
      _scrollToKey(_itemKey);
    } else if (_errQty != null) {
      _scrollToKey(_qtyKey);
    } else if (_errUnit != null) {
      _scrollToKey(_unitKey);
    } else if (_errKgPerBag != null) {
      _scrollToKey(_kgPerBagKey);
    } else if (_errLanding != null) {
      _scrollToKey(_landingKey);
    } else if (_errSelling != null) {
      _scrollToKey(_sellingKey);
    }
  }

  void _focusItemNameField() {
    _itemFocus.requestFocus();
    _scrollToKey(_itemKey);
  }

  void _focusQtyUnitEntry() {
    _qtyFocus.requestFocus();
    _scrollToKey(_qtyKey);
  }

  Map<String, String> _snapshotFields() {
    return {
      'item': _itemCtrl.text,
      'qty': _qtyCtrl.text,
      'unit': _unitCtrl.text,
      'landing': _landingCtrl.text,
      'selling': _sellingCtrl.text,
      'disc': _discCtrl.text,
      'tax': _taxCtrl.text,
      'kgpb': _kgPerBagCtrl.text,
      'notes': _lineNotesCtrl.text,
    };
  }

  void _storeFieldBaseline() {
    _fieldBaseline = _snapshotFields();
  }

  bool _isDirtySheet() {
    final b = _fieldBaseline;
    if (b == null) return false;
    final n = _snapshotFields();
    for (final e in n.entries) {
      if ((b[e.key] ?? '') != e.value) return true;
    }
    return false;
  }

  void _popSheet<T extends Object?>([T? result]) {
    if (!mounted) return;
    popImperativeOrGo(
      context,
      fallbackGo: '/purchase',
      result: result,
    );
  }

  Future<void> _confirmDiscardAndPop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You will lose edits to this line.'),
        actions: [
          TextButton(
            onPressed: () => popOverlay(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => popOverlay(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _popSheet();
  }

  Future<void> _handleLeadingBack() async {
    if (_isDirtySheet()) {
      await _confirmDiscardAndPop();
      return;
    }
    _popSheet();
  }

  bool _showHsnFooterMeta() {
    final tax = _parseD(_taxCtrl.text) ?? 0;
    if (tax > 1e-9) return true;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u == 'bag' || u == 'sack') return true;
    return _activeClassification().type == UnitType.weightBag;
  }

  Widget? _suggestOneBagInsteadOfKgBanner() {
    final c = _activeClassification();
    final kn = c.kgFromName;
    if (kn == null || kn <= 0) return null;
    if (_unitCtrl.text.trim().toLowerCase() != 'kg') return null;
    final q = _qtyVal();
    if (q <= 0 || (q - kn).abs() > 0.01 * math.max(1.0, kn)) return null;
    final theme = Theme.of(context);
    final knLabel = (kn - kn.roundToDouble()).abs() < 1e-6
        ? '${kn.round()}'
        : kn.toStringAsFixed(1);
    return Material(
      color: const Color(0xFFE0F2FE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'This name looks like a $knLabel kg pack. Record as 1 bag instead?',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0369A1),
                  height: 1.25,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _unitCtrl.text = 'bag';
                  _qtyCtrl.text = '1';
                  _weightPricing = true;
                  _kgPerUnit = kn;
                  _kgPerBagCtrl.text = _fmtQty(kn);
                  _recomputeModeFromUnitAndCatalog();
                });
              },
              child: const Text('Use 1 bag'),
            ),
          ],
        ),
      ),
    );
  }

  /// Bag qty × kg/bag implies a huge total —” user may have meant **kg** as the unit.
  Widget? _didYouMeanKgNotBagsBanner() {
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return null;
    final k = _kgPer();
    if (k == null || k <= 0) return null;
    final q = _qtyVal();
    if (q <= 0) return null;
    final totalK = q * k;
    if (totalK <= 50000 && q <= 200) return null;
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Did you mean ${_inQtyWtFmt.format(q)} kg (not ${_inQtyWtFmt.format(q)} bags × ${_fmtQty(k)} kg)?',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A3412),
                  height: 1.25,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _unitCtrl.text = 'kg';
                  _qtyCtrl.text = _fmtQty(q);
                  _weightPricing = false;
                  _kgPerUnit = null;
                  _kgPerBagCtrl.clear();
                  _recomputeModeFromUnitAndCatalog();
                });
              },
              child: const Text('Use kg'),
            ),
          ],
        ),
      ),
    );
  }

  /// Catalog saved as loose kg but name/weight imply bag —” link to item edit.
  Widget? _catalogLooseKgMisconfigFixBanner() {
    final id = _selectedCatalogItemId?.trim();
    if (id == null || id.isEmpty) return null;
    final row = _catalogRowById(id);
    if (!catalogItemMisconfiguredAsLooseKgWithBagWeight(row)) return null;
    final unitLow = _unitCtrl.text.trim().toLowerCase();
    final usedBag = unitLow == 'bag' || unitLow == 'sack';
    final blocked = _errUnit != null && _errUnit!.contains('loose KG');
    if (!blocked && !usedBag) return null;
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'This item should use bag tracking (e.g. 30 kg per bag). '
                'Fix the catalog unit, then enter bags here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A3412),
                  height: 1.25,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                context.push('/catalog/item/$id/edit');
              },
              child: const Text('Fix unit'),
            ),
          ],
        ),
      ),
    );
  }

  /// Name encodes a weight bag but unit is kg —” qty is **kg**, not bag count.
  Widget? _nameImpliesBagButKgUnitBanner() {
    final c = _activeClassification();
    if (c.type != UnitType.weightBag ||
        c.kgFromName == null ||
        c.kgFromName! <= 0) {
      return null;
    }
    if (_unitCtrl.text.trim().toLowerCase() != 'kg') return null;
    final theme = Theme.of(context);
    final kn = c.kgFromName!;
    final knLabel = (kn - kn.roundToDouble()).abs() < 1e-6
        ? '${kn.round()}'
        : kn.toStringAsFixed(1);
    return Material(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          'Name looks like a $knLabel kg/bag item —” quantity is in **kg**, not bags. Switch unit to bag to count bags.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF065F46),
            height: 1.25,
          ),
        ),
      ),
    );
  }

  /// Selling stored per line unit on the wire; weight mode: multiply per-kg × kg_per_unit.
  /// Call only after validation; [sell] must be non-null and >= 0.
  double _sellingForPayloadForWire(double sell) {
    if (_ratesPerKgEconomics) {
      final k = _kgPer()!;
      return sell * k;
    }
    return sell;
  }

  Map<String, dynamic>? _validateAndBuildLine() {
    final name = _itemCtrl.text.trim();
    final qty = _qtyVal();
    final unit = _unitCtrl.text.trim();
    final rateIn = _ratesPerKgEconomics
        ? (_landingParsedAsPerKg() ?? 0)
        : (_parseD(_landingCtrl.text) ?? 0);
    final rate = rateIn;

    final catalogId = _selectedCatalogItemId;
    final rowSnap = catalogId != null && catalogId.isNotEmpty
        ? _catalogRowById(catalogId)
        : null;
    final clf = UnitClassifier.classify(
      itemName: name,
      lineUnit: unit,
      catalogDefaultUnit: rowSnap?['default_unit']?.toString(),
      catalogDefaultKgPerBag: _catalogKpb(rowSnap),
      categoryName: rowSnap?['category_name']?.toString() ??
          rowSnap?['category']?.toString(),
      subcategoryName: rowSnap?['subcategory_name']?.toString() ??
          rowSnap?['subcategory']?.toString(),
    );

    setState(() {
      if (name.isEmpty) {
        _errItem = 'Enter an item';
      } else if (catalogId == null || catalogId.isEmpty) {
        _errItem = 'Pick a catalog item from the list';
      } else {
        _errItem = null;
      }
      final unitLow = unit.toLowerCase();
      final fracPack = (unitLow == 'bag' ||
              unitLow == 'sack' ||
              unitLow == 'box' ||
              unitLow == 'tin') &&
          (qty - qty.roundToDouble()).abs() > 1e-6;
      _errQty = qty <= 0
          ? 'Quantity must be greater than zero'
          : fracPack
              ? 'Use a whole number for $unitLow lines (no decimals)'
              : null;
      if (_errQty == null &&
          _qtyEntryMode == 'kg' &&
          (unitLow == 'bag' || unitLow == 'sack')) {
        final k = _kgPer();
        final enteredKg = _enteredKgForBagMode();
        if (k != null && k > 0 && enteredKg != null && enteredKg > 0) {
          final bags = enteredKg / k;
          if (!_bagQtyIsWhole(bags)) {
            _errQty = 'Kg must convert to a whole bag count. '
                'Use a multiple of ${_fmtQty(k)} kg.';
          }
        }
      }
      final unitProfileErr =
          validatePurchaseLineUnitAgainstCatalog(rowSnap, unit);
      _errUnit = unitProfileErr ??
          (unit.isEmpty ? 'Unit is required' : null);
      _errKgPerBag = null;
      if (unitLow == 'bag' || unitLow == 'sack') {
        var k = _kgPer();
        // Auto-derive from item name if still null (e.g. "30 KG" in name â†’ 30)
        if ((k == null || k <= 0) && _kgPerBagCtrl.text.trim().isEmpty) {
          if (clf.kgFromName != null && clf.kgFromName! > 0) {
            k = clf.kgFromName;
            _kgPerUnit = clf.kgFromName;
            _weightPricing = true;
            _kgPerBagCtrl.text = _fmtQty(clf.kgFromName!);
          }
        }
        if (k == null || k <= 0) {
          _errKgPerBag =
              'Kg per bag is required for bag lines. Enter it below, or use the catalog prompt when offered.';
        } else {
          _errKgPerBag = null; // Clear any stale error
        }
      } else if (clf.type == UnitType.weightBag) {
        final k = _kgPer();
        _errKgPerBag = (k == null || k <= 0) ? 'Kg per bag required' : null;
      }
      if (_ratesPerKgEconomics) {
        _errLanding = rateIn <= 0
            ? (_rateFieldsPerKg
                ? 'Enter a purchase rate per kg greater than zero'
                : 'Enter a purchase rate per bag greater than zero')
            : null;
      } else {
        _errLanding =
            rateIn <= 0 ? 'Enter a purchase rate greater than zero' : null;
      }
      final sellT = _sellingCtrl.text.trim();
      if (sellT.isEmpty) {
        _errSelling = null;
      } else {
        final sv = _parseD(sellT);
        if (sv == null) {
          _errSelling = 'Enter a valid selling rate';
        } else if (sv < 0) {
          _errSelling = 'Selling rate cannot be negative';
        } else {
          _errSelling = null;
        }
      }
      // HSN is optional on purchase lines (backend accepts null); do not block save.
      _errHsn = null;
    });

    if (_errItem != null ||
        _errQty != null ||
        _errUnit != null ||
        _errKgPerBag != null ||
        _errLanding != null ||
        _errSelling != null) {
      _scrollToFirstBlockingError();
      return null;
    }
    final disc = _parseD(_discCtrl.text);
    final sellSt = _sellingCtrl.text.trim();

    final m = <String, dynamic>{
      if (_selectedCatalogItemId != null && _selectedCatalogItemId!.isNotEmpty)
        'catalog_item_id': _selectedCatalogItemId,
      'item_name': name,
      'qty': qty,
      'unit': unit,
    };

    if (_ratesPerKgEconomics) {
      final kpu = _kgPer()!;
      m['kg_per_unit'] = kpu;
      m['landing_cost_per_kg'] = rate;
      m['landing_cost'] = kpu * rate;
    } else {
      m['landing_cost'] = rate;
      m['purchase_rate'] = rate;
    }
    if (_ratesPerKgEconomics) m['purchase_rate'] = m['landing_cost'];
    final unitLow = unit.toLowerCase();
    // [Bug 1 fix] Default wholesale mode: BOX/TIN are count-only —” never write
    // weight fields, items_per_box, kg_per_box, weight_per_tin, or
    // weight_per_unit. The advanced inventory escape hatch is intentionally
    // off (_advancedInventoryEnabled = false in master rebuild).
    final isBoxOrTin = unitLow == 'box' || unitLow == 'tin';
    if (isBoxOrTin && _advancedInventoryEnabled) {
      if (unitLow == 'box') {
        if (clf.type == UnitType.multiPackBox || !_boxFixedWeight) {
          m['box_mode'] = 'items_per_box';
          final items = _parseD(_itemsPerBoxCtrl.text);
          final weight = _parseD(_weightPerItemCtrl.text);
          if (items != null) m['items_per_box'] = items;
          if (weight != null) m['weight_per_item'] = weight;
        } else if (clf.type == UnitType.singlePack) {
          final kg = _parseD(_kgPerBoxCtrl.text) ?? clf.kgFromName ?? _kgPer();
          if (kg != null && kg > 0) {
            m['box_mode'] = 'fixed_weight_box';
            m['kg_per_box'] = kg;
            m['weight_per_unit'] = kg;
          }
        } else {
          if (_boxFixedWeight) {
            m['box_mode'] = 'fixed_weight_box';
            final kg = _parseD(_kgPerBoxCtrl.text) ?? _kgPer();
            if (kg != null) {
              m['kg_per_box'] = kg;
              m['weight_per_unit'] = kg;
            }
          } else {
            m['box_mode'] = 'items_per_box';
            final items = _parseD(_itemsPerBoxCtrl.text);
            final weight = _parseD(_weightPerItemCtrl.text);
            if (items != null) m['items_per_box'] = items;
            if (weight != null) m['weight_per_item'] = weight;
          }
        }
      } else if (unitLow == 'tin') {
        final wt =
            _parseD(_weightPerTinCtrl.text) ?? clf.kgFromName ?? _kgPer();
        if (wt != null) {
          m['weight_per_tin'] = wt;
          m['weight_per_unit'] = wt;
        }
      }
    }
    // For default wholesale mode: do not emit kg_per_unit / weight_per_unit /
    // box_mode for box/tin. The line carries qty + purchase_rate only.
    if (isBoxOrTin && !_advancedInventoryEnabled) {
      m.remove('kg_per_unit');
      m.remove('weight_per_unit');
    }
    if (!widget.omitLineFreightDeliveredBilltyDiscount) {
      if (disc != null && disc > 0) m['discount'] = disc;
    }
    applyTaxPercentToPurchaseLineMap(
      m,
      taxOn: _taxMode != TaxMode.none,
      typedTaxPercent: _parseD(_taxCtrl.text),
      catalogTaxPercent: _numericTaxFromCatalogRow(),
    );
    m['tax_mode'] = taxModeToWire(_taxMode);
    if (sellSt.isNotEmpty) {
      final sellIn = _sellingParsedAsPerKg() ?? _parseD(sellSt)!;
      final sellParsed = sellIn;
      m['selling_cost'] = _sellingForPayloadForWire(sellParsed);
      m['selling_rate'] = m['selling_cost'];
    }
    if (!widget.omitLineFreightDeliveredBilltyDiscount) {
      m['freight_type'] = _freightType;
      final fv = _parseD(_freightCtrl.text);
      final dr = _parseD(_deliveredCtrl.text);
      final br = _parseD(_billtyCtrl.text);
      if (fv != null) m['freight_value'] = fv;
      if (dr != null) m['delivered_rate'] = dr;
      if (br != null) m['billty_rate'] = br;
    }
    final hOut = _hsnCode?.trim() ?? '';
    if (hOut.isNotEmpty) m['hsn_code'] = hOut;
    final icOut = _itemCode?.trim() ?? '';
    if (icOut.isNotEmpty) m['item_code'] = icOut;
    final note = _lineNotesCtrl.text.trim();
    if (note.isNotEmpty) m['description'] = note;
    return m;
  }

  void _resetAfterAdd() {
    setState(() {
      _itemCtrl.clear();
      _selectedCatalogItemId = null;
      _weightPricing = false;
      _kgPerUnit = null;
      _qtyCtrl.text = '1';
      _unitCtrl.text = 'kg';
      _landingCtrl.clear();
      _discCtrl.clear();
      _taxCtrl.clear();
      _sellingCtrl.clear();
      _kgPerBagCtrl.clear();
      _freightCtrl.clear();
      _deliveredCtrl.clear();
      _billtyCtrl.clear();
      _itemsPerBoxCtrl.clear();
      _weightPerItemCtrl.clear();
      _kgPerBoxCtrl.clear();
      _weightPerTinCtrl.clear();
      _freightType = 'separate';
      _boxFixedWeight = true;
      _errItem = null;
      _errQty = null;
      _errUnit = null;
      _errLanding = null;
      _errSelling = null;
      _errKgPerBag = null;
      _errHsn = null;
      _hsnCode = null;
      _itemCode = null;
      _lineNotesCtrl.clear();
      _lastPurchaseAutofillHint = null;
      _rateFieldsPerKg = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _itemFocus.requestFocus();
        _storeFieldBaseline();
      }
    });
  }

  void _commit({required bool closeSheet}) {
    if (_commitInFlight) return;
    final line = _validateAndBuildLine();
    if (line == null) {
      if (mounted) {
        final msg = _errKgPerBag ??
            _errQty ??
            _errItem ??
            _errUnit ??
            _errLanding ??
            _errSelling;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
            ),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToFirstBlockingError();
          });
        }
      }
      return;
    }
    _commitInFlight = true;
    widget.onCommitted(line);
    final itemId = _selectedCatalogItemId;
    final rate = _parseD(_landingCtrl.text);
    final qty = _parseD(_qtyCtrl.text);
    if (itemId != null && itemId.isNotEmpty) {
      if (rate != null && rate > 0) {
        unawaited(PurchaseSmartDefaults.saveLastRateForItem(itemId, rate));
      }
      if (qty != null && qty > 0) {
        unawaited(PurchaseSmartDefaults.recordQtyForItem(itemId, qty));
      }
    }
    if (!widget.fullPage) {
      if (closeSheet) {
        _popSheet();
      } else {
        _resetAfterAdd();
      }
      _commitInFlight = false;
      return;
    }
    // Full-screen page: caller may chain another add via pop result.
    _popSheet<bool>(!closeSheet);
    _commitInFlight = false;
  }

  String _purchaseRateLabel(bool _) {
    final resolved = _resolvedUnitContext();
    if (!_showPerKgLandingLabels && resolved.unitConfidence >= 60) {
      return resolved.purchaseRateFieldLabel;
    }
    final sfx = unit_lbl.purchaseRateSuffix(_draftLineForLabelsOnly());
    if (widget.fullPage) {
      return 'Purchase Rate (₹/$sfx) *';
    }
    return 'Landing cost (₹/$sfx) *';
  }

  String _sellingRateLabel(bool _) {
    const optional = 'Selling rate (optional)';
    final resolved = _resolvedUnitContext();
    if (!_showPerKgLandingLabels && resolved.unitConfidence >= 60) {
      return optional;
    }
    final sfx = unit_lbl.sellingRateSuffix(_draftLineForLabelsOnly());
    if (widget.fullPage) {
      return 'Selling rate (optional) (₹/$sfx)';
    }
    return 'Selling rate (optional) (₹/$sfx)';
  }

  String _catalogUnitChipLabel(Map<String, dynamic> row) {
    for (final key in [
      'unit_type',
      'packaging_type',
      'default_purchase_unit',
      'default_unit',
    ]) {
      final v = row[key]?.toString().trim();
      if (v != null && v.isNotEmpty) {
        final u = v.toLowerCase();
        if (u == 'piece' || u == 'pcs') return 'Piece';
        if (u == 'bag' || u == 'sack') return 'Bag';
        if (u == 'box') return 'Box';
        if (u == 'kg') return 'Kg';
        return v[0].toUpperCase() + v.substring(1);
      }
    }
    return 'Kg';
  }

  static const _kCatalogLabelSep = ' · ';

  String _catalogSearchLabelForRow(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    if (name.isEmpty) return name;
    final chip = _catalogUnitChipLabel(row);
    return chip.isEmpty ? name : '$name$_kCatalogLabelSep$chip';
  }

  String _catalogNameFromPickerLabel(String label) {
    final t = label.trim();
    final i = t.lastIndexOf(_kCatalogLabelSep);
    if (i > 0) return t.substring(0, i).trim();
    return t;
  }

  bool _itemTextMatchesSelectedCatalog(String text) {
    if (_selectedCatalogItemId == null || _selectedCatalogItemId!.isEmpty) {
      return false;
    }
    final row = _catalogRowById(_selectedCatalogItemId!);
    if (row == null) return false;
    final t = text.trim();
    final name = (row['name']?.toString() ?? '').trim();
    if (t == name) return true;
    return t == _catalogSearchLabelForRow(row);
  }

  String _catalogSearchSuggestionSubtitle(Map<String, dynamic> row) {
    final lines = <String>[];
    final unitChip = _catalogUnitChipLabel(row);
    final unit = row['default_unit']?.toString().trim();
    final lpp = row['last_purchase_price'];
    double? price;
    if (lpp is num && lpp > 0) {
      price = lpp.toDouble();
    } else if (lpp != null) {
      price = double.tryParse(lpp.toString());
    }

    final headParts = <String>[unitChip];
    if (unit != null && unit.isNotEmpty && unit.toLowerCase() != unitChip.toLowerCase()) {
      headParts.add(unit);
    }
    final stockRaw = row['current_stock'];
    final stockQty = stockRaw is num
        ? stockRaw.toDouble()
        : double.tryParse(stockRaw?.toString() ?? '');
    if (stockQty != null) {
      headParts.add('Stock ${stockDisplayPrimary(stockQty, unit ?? '')}');
    }
    if (price != null && price > 0) {
      headParts.add('Last buy ₹${_fmtMoney(price)}');
    }
    if (headParts.isNotEmpty) lines.add(headParts.join(' · '));

    final rawDate = row['last_purchase_date']?.toString();
    DateTime? pd;
    if (rawDate != null && rawDate.length >= 10) {
      pd = DateTime.tryParse(rawDate.substring(0, 10));
    }
    if (pd != null) {
      final days = DateTime.now().difference(pd).inDays;
      final ago = days == 0
          ? 'today'
          : days == 1
              ? 'yesterday'
              : '$days days ago';
      lines.add('Last buy ${DateFormat('d MMM yyyy').format(pd)} · $ago');
    }

    final del = row['last_purchase_delivered'];
    if (del == true) {
      lines.add('Delivered');
    } else if (del == false) {
      lines.add('Not delivered');
    }

    if (lines.isEmpty) return unit ?? '';
    return lines.join('\n');
  }

  Widget _buildPurchaseSellingRateRow(
    bool showPerKgFields, {
    bool preferVertical = false,
  }) {
    return PurchaseItemEntryRateSection(
      showPerKgFields: showPerKgFields,
      preferVertical: preferVertical,
      landingCtrl: _landingCtrl,
      sellingCtrl: _sellingCtrl,
      landingFocus: _landingFocus,
      sellingFocus: _sellingFocus,
      landingKey: _landingKey,
      sellingKey: _sellingKey,
      landingLabel: _purchaseRateLabel(showPerKgFields),
      sellingLabel: _sellingRateLabel(showPerKgFields),
      errLanding: _errLanding,
      errSelling: _errSelling,
      decimalFormatter: _decimalFormatter,
      textFieldScrollPadding: _textFieldScrollPadding,
      deco: _deco,
      onFieldChanged: () {
        _clearFieldErrors();
        _schedulePreviewRebuild();
      },
    );
  }

  Widget _buildTaxModeChips(ThemeData theme) {
    return PurchaseItemEntryTaxSection(
      taxMode: _taxMode,
      onPick: (m) async {
        if (m == _taxMode) return;
        setState(() {
          _taxMode = m;
          if (m == TaxMode.none) {
            _taxCtrl.clear();
          } else {
            final rowTax = _numericTaxFromCatalogRow();
            if (rowTax != null && rowTax > 0 && _taxCtrl.text.trim().isEmpty) {
              _taxCtrl.text = StrictDecimal.fromObject(rowTax).format(2);
            }
          }
        });
        _taxModeNotifier.value = m;
        final p = widget.gstPrefs ?? await SharedPreferences.getInstance();
        await PurchaseLineTaxModePrefs.save(p, m);
        if (mounted) _schedulePreviewRebuild();
      },
    );
  }


  /// Picks line unit: when the item has a bag weight but purchase unit is
  /// `kg` in the catalog, prefer the physical [default_unit] (bag) so
  /// per-kg × kg/bag math applies.
  String _lineUnitForCatalog(
    Map<String, dynamic> row, {
    required double? kpbD,
  }) {
    final dpu = row['default_purchase_unit']?.toString().trim();
    final du = row['default_unit']?.toString().trim();
    if (kpbD != null && kpbD > 0) {
      if (du != null &&
          _isWeightUnit(du) &&
          (dpu == null || dpu.toLowerCase() == 'kg')) {
        return du;
      }
    }
    String? pick() {
      if (dpu != null && dpu.isNotEmpty) return dpu;
      if (du != null && du.isNotEmpty) return du;
      return null;
    }

    final chosen = pick() ?? 'kg';
    final low = chosen.toLowerCase();
    // DB/catalog often store consumer packs as `piece`; wholesale UI uses tin/box/kg.
    if (low == 'piece' || low == 'pcs' || low == 'pieces') {
      final nm = (row['name']?.toString() ?? '').toUpperCase();
      if (nm.contains('TIN') || nm.contains('CAN') || nm.contains('JAR')) {
        return 'tin';
      }
      if (RegExp(r'\d+\s*(GM|GRAMS?|ML|LTR|LITERS?)\b', caseSensitive: false)
          .hasMatch(nm)) {
        return 'tin';
      }
      if (nm.contains('BOX') || nm.contains('CTN') || nm.contains('CARTON')) {
        return 'box';
      }
    }
    return chosen;
  }

  void _clearKgIfNotDerivedFromName() {
    if (!_isBagFamilyUnit()) {
      _kgPerUnit = null;
      _weightPricing = false;
      _kgPerBagCtrl.clear();
      return;
    }
    // Don't clear if name-derived kg is available
    final clf = _activeClassification();
    if (clf.kgFromName != null && clf.kgFromName! > 0) {
      _kgPerUnit = clf.kgFromName;
      _weightPricing = true;
      if (_kgPerBagCtrl.text.isEmpty) {
        _kgPerBagCtrl.text = _fmtQty(clf.kgFromName!);
      }
      return;
    }
    _kgPerUnit = null;
    _weightPricing = false;
    // Don't clear _kgPerBagCtrl if user typed something
    if (_parseD(_kgPerBagCtrl.text) == null) {
      _kgPerBagCtrl.clear();
    }
  }

  void _recomputeModeFromUnitAndCatalog() {
    if (_selectedCatalogItemId == null || _selectedCatalogItemId!.isEmpty) {
      return;
    }
    final u0 = _unitCtrl.text.trim().toLowerCase();
    if (u0 != 'bag' && u0 != 'sack') return;
    final row = _catalogRowById(_selectedCatalogItemId!);
    if (row == null) return;
    final kpb = row['default_kg_per_bag'];
    final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
    if (kpbD == null) {
      if (_kgPerUnit != null && _hasCatalogKg() == false) {
        setState(() {
          _clearKgIfNotDerivedFromName();
        });
      }
      return;
    }
    if (_kgPerUnit != kpbD || !_weightPricing) {
      setState(() {
        _weightPricing = true;
        _kgPerUnit = kpbD;
        _kgPerBagCtrl.text = _fmtQty(kpbD);
      });
    }
  }

  Future<void> _offerCatalogKgPerBagSheetIfNeeded(
      Map<String, dynamic>? row) async {
    if (!mounted || row == null || widget.persistCatalogBagWeight == null) {
      return;
    }
    final cid = _selectedCatalogItemId?.trim();
    if (cid == null || cid.isEmpty) return;
    final u = _unitCtrl.text.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    final k = _kgPer();
    if (k != null && k > 0) return;
    final kpb = _catalogKpb(row);
    if (kpb != null && kpb > 0) return;

    // NEW: If item name contains kg info, auto-use it instead of showing modal
    final clf = _activeClassification();
    if (clf.kgFromName != null && clf.kgFromName! > 0) {
      setState(() {
        _kgPerUnit = clf.kgFromName;
        _weightPricing = true;
        _kgPerBagCtrl.text = _fmtQty(clf.kgFromName!);
      });
      return; // â† Don't show the blocking sheet
    }

    final currentName = (row['name']?.toString() ?? _itemCtrl.text).trim();
    if (currentName.isEmpty) return;

    final kgCtrl = TextEditingController();
    try {
      final kgOut = await showHexaBottomSheet<double>(
        context: context,
        compact: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: StatefulBuilder(
              builder: (ctx2, setModal) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Missing bag weight',
                        style: Theme.of(ctx2).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter kg per bag for "$currentName" so totals calculate correctly. '
                        'This is saved to the catalog.',
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: kgCtrl,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'KG per bag',
                          suffixText: 'kg/bag',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (ctx3) {
                          final kg = double.tryParse(kgCtrl.text.trim());
                          if (kg == null || kg <= 0) {
                            return const SizedBox.shrink();
                          }
                          final base =
                              _stripKgSuffixForCatalogDisplay(currentName);
                          final suffix = (kg - kg.roundToDouble()).abs() < 1e-6
                              ? '${kg.round()}KG'
                              : '${kg.toStringAsFixed(1)}KG';
                          final newName = '$base $suffix'.trim();
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Item will be renamed to:\n"$newName"',
                              style: const TextStyle(
                                color: Color(0xFF1A7A6A),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Skip'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final kg = double.tryParse(kgCtrl.text.trim());
                                if (kg != null && kg > 0) {
                                  Navigator.pop(context, kg);
                                }
                              },
                              child: const Text('DONE +'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      );
      if (!mounted || kgOut == null || kgOut <= 0) return;

      final base = _stripKgSuffixForCatalogDisplay(currentName);
      final suffix = (kgOut - kgOut.roundToDouble()).abs() < 1e-6
          ? '${kgOut.round()}KG'
          : '${kgOut.toStringAsFixed(1)}KG';
      final newName = '$base $suffix'.trim();
      await widget.persistCatalogBagWeight!(
        catalogItemId: cid,
        newName: newName,
        defaultKgPerBag: kgOut,
      );
      if (!mounted) return;
      final merged = Map<String, dynamic>.from(row);
      merged['name'] = newName;
      merged['default_kg_per_bag'] = kgOut;
      setState(() {
        _catalogFetchById[cid] = merged;
        _applyBagKgFromCatalog(merged, kgOut);
        _itemCtrl.text = newName;
        _errKgPerBag = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $kgOut kg/bag for "$newName"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      logSilencedApiError(e, StackTrace.current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save catalog weight. ${userFacingError(e)}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      kgCtrl.dispose();
    }
  }

  void _onItemSelected(String id, String name) {
    if (id.isEmpty) return;
    _suppressCatalogTextUnlink = true;
    unawaited(
      _onCatalogPickAsync(InlineSearchItem(id: id, label: name))
          .whenComplete(() {
        if (mounted) _suppressCatalogTextUnlink = false;
      }),
    );
  }

  /// Seeds ₹/kg + bag totals from catalog default landing/selling vs [kg].
  void _applyBagKgFromCatalog(Map<String, dynamic> row, double kg) {
    _weightPricing = true;
    _kgPerUnit = kg;
    _kgPerBagCtrl.text = _fmtQty(kg);
    var perKg = 0.0;
    final lp = row['default_landing_cost'];
    final lpD = _numD(lp);
    if (lpD != null && lpD > 0) {
      perKg = StrictDecimal.fromObject(lpD)
          .divide(StrictDecimal.fromObject(kg), scale: 6)
          .toDouble();
    }
    _landingCtrl.text = perKg > 0 ? _fmtMoney(perKg) : '';
    final sc = row['default_selling_cost'];
    final scD = _numD(sc);
    if (scD != null) {
      _sellingCtrl.text = _fmtMoney(
        StrictDecimal.fromObject(scD)
            .divide(StrictDecimal.fromObject(kg), scale: 6)
            .toDouble(),
      );
    } else {
      _sellingCtrl.clear();
    }
  }

  /// Per-line-unit rates from catalog when not using bag ₹/kg snapshot.
  void _applyFlatUnitFromCatalog(Map<String, dynamic> row) {
    _clearKgIfNotDerivedFromName();
    var rate = 0.0;
    final lp = row['default_landing_cost'];
    final lpD = _numD(lp);
    if (lpD != null && lpD > 0) rate = lpD;
    _landingCtrl.text = rate > 0 ? _fmtMoney(rate) : '';
    final sc2 = row['default_selling_cost'];
    final scD = _numD(sc2);
    if (scD != null) {
      _sellingCtrl.text = _fmtMoney(scD);
    } else {
      _sellingCtrl.clear();
    }
  }

  /// Applies [row] only — no merge with a prior line (call after fresh fetch or list row).
  void _applyCatalogRowToLineState(
    Map<String, dynamic> row, {
    required String catalogId,
    required String nameFallback,
  }) {
    final name = (row['name']?.toString() ?? nameFallback).trim();
    final displayName = name.isNotEmpty ? name : nameFallback;
    final kpb = row['default_kg_per_bag'];
    final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
    final catalogKpbFull = _catalogKpb(row);

    final classification = UnitClassifier.classify(
      itemName: displayName,
      lineUnit: '',
      catalogDefaultUnit: row['default_unit']?.toString(),
      catalogDefaultKgPerBag: catalogKpbFull,
      categoryName:
          row['category_name']?.toString() ?? row['category']?.toString(),
      subcategoryName:
          row['subcategory_name']?.toString() ?? row['subcategory']?.toString(),
    );

    final wire = _wireUnitFromClassification(
      c: classification,
      row: row,
      kpbD: kpbD,
      displayName: displayName,
    );
    final uLowWire = wire.toLowerCase();

    final bool boxUsesItems =
        classification.type == UnitType.multiPackBox && uLowWire == 'box';

    setState(() {
      _lastPurchaseAutofillHint = null;
      _selectedCatalogItemId = catalogId;
      _itemCtrl.text = displayName;
      _hsnCode = _hsnFromRow(row);
      _itemCode = _itemCodeFromRow(row);
      _unitCtrl.text = wire;

      if (uLowWire == 'box') {
        if (boxUsesItems) {
          _boxFixedWeight = false;
        } else {
          _boxFixedWeight = true;
        }
      }
      _unitDetectHint =
          _hintFromClassification(classification, wire.toLowerCase());

      if (classification.type == UnitType.weightBag) {
        final kg = kpbD ?? classification.kgFromName;
        if (kg != null && kg > 0) {
          _applyBagKgFromCatalog(row, kg);
        } else {
          _applyFlatUnitFromCatalog(row);
        }
      } else if (uLowWire == 'box') {
        _applyFlatUnitFromCatalog(row);
        _itemsPerBoxCtrl.clear();
        _weightPerItemCtrl.clear();
        if (boxUsesItems) {
          _kgPerBoxCtrl.clear();
        } else if (classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _kgPerBoxCtrl.text = _fmtQty(classification.kgFromName!);
        } else {
          _kgPerBoxCtrl.clear();
        }
      } else if (uLowWire == 'tin') {
        _applyFlatUnitFromCatalog(row);
        _kgPerBagCtrl.clear();
        _kgPerUnit = null;
        _weightPricing = false;
        _weightPerTinCtrl.clear();
        if (classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _weightPerTinCtrl.text = _fmtQty(classification.kgFromName!);
        }
      } else {
        if (kpbD != null && kpbD > 0) {
          _applyBagKgFromCatalog(row, kpbD);
        } else {
          _applyFlatUnitFromCatalog(row);
        }
      }

      if (_taxMode != TaxMode.none) {
        final tax = _numD(row['tax_percent']);
        _taxCtrl.text = tax != null && tax > 0
            ? StrictDecimal.fromObject(tax).format(2)
            : '';
      }
      _errItem = null;
    });
  }

  String? _hintForLastPurchaseDefaults(Map<String, dynamic> d) {
    final src = d['source']?.toString();
    if (d.isEmpty || src == null || src == 'none') return null;
    final supplier = d['supplier_name']?.toString().trim();
    final dateRaw = d['purchase_date']?.toString().trim();
    final dateShort = (dateRaw != null && dateRaw.length >= 10)
        ? dateRaw.substring(0, 10)
        : dateRaw;
    final pr = _numD(d['purchase_rate'] ?? d['landing_cost']);
    final buf = StringBuffer('Filled from last purchase');
    if (pr != null && pr > 0) {
      buf.write(' · rate ₹');
      buf.write(pr.toStringAsFixed(2));
    }
    if (supplier != null && supplier.isNotEmpty) {
      buf.write(' · ');
      buf.write(supplier);
    }
    if (dateShort != null && dateShort.isNotEmpty) {
      buf.write(' · ');
      buf.write(dateShort);
    }
    buf.write('.');
    return buf.toString();
  }

  Future<void> _applyPrefsSmartDefaults(String itemId) async {
    if (itemId.isEmpty || !mounted) return;
    final rate = await PurchaseSmartDefaults.loadLastRateForItem(itemId);
    final hist = await PurchaseSmartDefaults.loadQtyHistoryForItem(itemId);
    if (!mounted) return;
    setState(() {
      if (rate != null && rate > 0 && _landingCtrl.text.trim().isEmpty) {
        _landingCtrl.text = _fmtMoney(rate);
        _lastPurchaseAutofillHint =
            'Filled from your last entry on this device.';
      }
      if (_qtyCtrl.text.trim().isEmpty && hist.isNotEmpty) {
        _qtyCtrl.text = _fmtQty(
          PurchaseSmartDefaults.suggestQty(hist).toDouble(),
        );
      }
    });
  }

  void _applyLastDefaults(Map<String, dynamic> d) {
    final src = d['source']?.toString();
    if (d.isEmpty || src == null || src == 'none') {
      if (mounted) {
        setState(() => _lastPurchaseAutofillHint = null);
      }
      final itemId = _selectedCatalogItemId;
      if (itemId != null && itemId.isNotEmpty) {
        unawaited(_applyPrefsSmartDefaults(itemId));
      }
      return;
    }
    widget.onDefaultsResolved?.call(d);
    final unit = d['unit']?.toString().trim();
    final kpu = _numD(d['weight_per_unit'] ?? d['kg_per_unit']);
    final purchaseRate = _numD(d['purchase_rate'] ?? d['landing_cost']);
    final sellingRate = _numD(d['selling_rate'] ?? d['selling_cost']);
    final taxPercent = _numD(d['tax_percent']);
    final freight = _numD(d['freight_value'] ?? d['freight_amount']);
    final delivered = _numD(d['delivered_rate']);
    final billty = _numD(d['billty_rate']);
    final itemsPerBox = _numD(d['items_per_box']);
    final weightPerItem = _numD(d['weight_per_item']);
    final kgPerBox = _numD(d['kg_per_box']);
    final weightPerTin = _numD(d['weight_per_tin']);
    setState(() {
      if (unit != null && unit.isNotEmpty) {
        _unitCtrl.text = unit;
      }
      if (kpu != null && kpu > 0) {
        final u = _unitCtrl.text.trim().toLowerCase();
        if (u == 'box') {
          _kgPerBoxCtrl.text = _fmtQty(kpu);
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        } else if (u == 'tin') {
          _weightPerTinCtrl.text = _fmtQty(kpu);
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        } else {
          _weightPricing = true;
          _kgPerUnit = kpu;
          _kgPerBagCtrl.text = _fmtQty(kpu);
        }
      }
      if (_taxMode != TaxMode.none) {
        if (taxPercent != null && taxPercent >= 0) {
          _taxCtrl.text = taxPercent > 0
              ? StrictDecimal.fromObject(taxPercent).format(2)
              : '';
        }
      }
      final ft = d['freight_type']?.toString();
      if (ft == 'included' || ft == 'separate') _freightType = ft!;
      if (freight != null && freight >= 0) {
        _freightCtrl.text = _fmtMoney(freight);
      }
      if (delivered != null && delivered >= 0) {
        _deliveredCtrl.text = _fmtMoney(delivered);
      }
      if (billty != null && billty >= 0) _billtyCtrl.text = _fmtMoney(billty);
      if (itemsPerBox != null && itemsPerBox > 0) {
        _itemsPerBoxCtrl.text = _fmtQty(itemsPerBox);
      }
      if (weightPerItem != null && weightPerItem > 0) {
        _weightPerItemCtrl.text = _fmtQty(weightPerItem);
      }
      if (kgPerBox != null && kgPerBox > 0) {
        _kgPerBoxCtrl.text = _fmtQty(kgPerBox);
      }
      if (weightPerTin != null && weightPerTin > 0) {
        _weightPerTinCtrl.text = _fmtQty(weightPerTin);
      }
      final bm = d['box_mode']?.toString();
      if (bm == 'items_per_box') {
        _boxFixedWeight = false;
      } else if (bm == 'fixed_weight_box') {
        _boxFixedWeight = true;
      } else {
        final rr = _rowForClassification();
        final bc = UnitClassifier.classify(
          itemName: _itemCtrl.text.trim(),
          lineUnit: _unitCtrl.text,
          catalogDefaultUnit: rr?['default_unit']?.toString(),
          catalogDefaultKgPerBag: _catalogKpb(rr),
          categoryName:
              rr?['category_name']?.toString() ?? rr?['category']?.toString(),
          subcategoryName: rr?['subcategory_name']?.toString() ??
              rr?['subcategory']?.toString(),
        );
        _adjustBoxFixedForClassification(bc);
      }
      final rr = _rowForClassification();
      final clfRates = UnitClassifier.classify(
        itemName: _itemCtrl.text.trim(),
        lineUnit: _unitCtrl.text,
        catalogDefaultUnit: rr?['default_unit']?.toString(),
        catalogDefaultKgPerBag: _catalogKpb(rr),
        categoryName:
            rr?['category_name']?.toString() ?? rr?['category']?.toString(),
        subcategoryName: rr?['subcategory_name']?.toString() ??
            rr?['subcategory']?.toString(),
      );
      final kEff = _kgPer();
      final lcpkApi = _numD(d['landing_cost_per_kg']);
      final isWeightBagRates =
          clfRates.type == UnitType.weightBag && kEff != null && kEff > 0;
      if (isWeightBagRates) {
        if (lcpkApi != null && lcpkApi > 0) {
          _rateFieldsPerKg = true;
          _landingCtrl.text = _fmtMoney(lcpkApi);
          if (sellingRate != null && sellingRate >= 0) {
            _sellingCtrl.text = _fmtMoney(sellingRate / kEff);
          }
        } else {
          _rateFieldsPerKg = false;
          if (purchaseRate != null && purchaseRate > 0) {
            _landingCtrl.text = _fmtMoney(purchaseRate);
          }
          if (sellingRate != null && sellingRate >= 0) {
            _sellingCtrl.text = _fmtMoney(sellingRate);
          }
        }
      } else {
        if (purchaseRate != null && purchaseRate > 0) {
          _landingCtrl.text = _fmtMoney(purchaseRate);
        }
        if (sellingRate != null && sellingRate >= 0) {
          _sellingCtrl.text = _fmtMoney(sellingRate);
        }
      }
      _lastPurchaseAutofillHint = _hintForLastPurchaseDefaults(d);
    });
  }

  void _scheduleLastDefaultsFetch(String catalogItemId, int seq) {
    _defaultsDebounceTimer?.cancel();
    final fetch = widget.resolveLastDefaults;
    if (fetch == null || widget.isEdit) return;
    _defaultsDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || seq != _catalogPickSeq) return;
      try {
        final defaults = await fetch(catalogItemId);
        if (!mounted || seq != _catalogPickSeq) return;
        _applyLastDefaults(defaults);
      } catch (_) {}
    });
  }

  Future<void> _onCatalogPickAsync(InlineSearchItem it) async {
    if (it.id.isEmpty) {
      _catalogPickSeq++;
      if (!mounted) return;
      setState(() {
        _selectedCatalogItemId = null;
        _weightPricing = false;
        _kgPerUnit = null;
        _kgPerBagCtrl.clear();
        _lastPurchaseAutofillHint = null;
        _unitDetectHint = null;
        _errItem = null;
        _hsnCode = null;
        _itemCode = null;
      });
      return;
    }

    final seq = ++_catalogPickSeq;
    final nameOnly = _catalogNameFromPickerLabel(it.label);

    // Id + catalog name committed before catalog resolve/network.
    if (mounted) {
      setState(() {
        _selectedCatalogItemId = it.id;
        _itemCtrl.value = TextEditingValue(
          text: nameOnly.isNotEmpty ? nameOnly : it.label,
          selection: TextSelection.collapsed(
            offset: (nameOnly.isNotEmpty ? nameOnly : it.label).length,
          ),
        );
        _errItem = null;
      });
    }

    Map<String, dynamic>? row = _catalogRowById(it.id);
    if (widget.resolveCatalogItem != null) {
      try {
        final fresh = await widget.resolveCatalogItem!(it.id);
        if (fresh.isNotEmpty && mounted) {
          setState(() {
            _catalogFetchById[it.id] = Map<String, dynamic>.from(fresh);
          });
          row = _catalogRowById(it.id);
        }
      } catch (_) {}
    }

    if (!mounted || seq != _catalogPickSeq) return;
    if (row == null) {
      final labelTrim = it.label.trim();
      final classification = UnitClassifier.classify(
        itemName: labelTrim,
        lineUnit: '',
        catalogDefaultUnit: null,
      );
      final wire = _wireUnitFromClassification(
        c: classification,
        row: null,
        kpbD: null,
        displayName: labelTrim,
      );
      final wLow = wire.toLowerCase();
      final boxItems =
          classification.type == UnitType.multiPackBox && wLow == 'box';

      setState(() {
        _selectedCatalogItemId = it.id;
        _itemCtrl.text = nameOnly.isNotEmpty ? nameOnly : it.label;
        _lastPurchaseAutofillHint = null;
        _errItem = null;
        _hsnCode = null;
        _itemCode = null;
        _taxCtrl.clear();
        _landingCtrl.clear();
        _sellingCtrl.clear();

        _unitCtrl.text = wire;
        if (wLow == 'box') {
          _itemsPerBoxCtrl.clear();
          _weightPerItemCtrl.clear();
          if (boxItems) {
            _boxFixedWeight = false;
            _kgPerBoxCtrl.clear();
          } else {
            _boxFixedWeight = true;
            if (classification.kgFromName != null &&
                classification.kgFromName! > 0) {
              _kgPerBoxCtrl.text = _fmtQty(classification.kgFromName!);
            } else {
              _kgPerBoxCtrl.clear();
            }
          }
        } else if (wLow != 'tin') {
          _kgPerBoxCtrl.clear();
        }
        if (wLow != 'box') {
          _itemsPerBoxCtrl.clear();
          _weightPerItemCtrl.clear();
        }
        if (wLow == 'tin') {
          _weightPerTinCtrl.clear();
          _boxFixedWeight = true;
          if (classification.kgFromName != null &&
              classification.kgFromName! > 0) {
            _weightPerTinCtrl.text = _fmtQty(classification.kgFromName!);
          }
        } else if (wLow != 'box') {
          _weightPerTinCtrl.clear();
        }

        if (classification.type == UnitType.weightBag &&
            classification.kgFromName != null &&
            classification.kgFromName! > 0) {
          _weightPricing = true;
          _kgPerUnit = classification.kgFromName;
          _kgPerBagCtrl.text = _fmtQty(classification.kgFromName!);
        } else {
          _weightPricing = false;
          _kgPerUnit = null;
          _kgPerBagCtrl.clear();
        }

        _unitDetectHint = _hintFromClassification(classification, wLow);
      });
      _scheduleLastDefaultsFetch(it.id, seq);
      unawaited(_applyPrefsSmartDefaults(it.id));
      return;
    }
    _applyCatalogRowToLineState(
      row,
      catalogId: it.id,
      nameFallback: it.label,
    );
    _scheduleLastDefaultsFetch(it.id, seq);
    unawaited(_applyPrefsSmartDefaults(it.id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || seq != _catalogPickSeq) return;
      unawaited(_offerCatalogKgPerBagSheetIfNeeded(_catalogRowById(it.id)));
    });
  }

  List<String> _gstSoftWarningMessages() {
    final out = <String>[];
    if (!widget.omitLineFreightDeliveredBilltyDiscount) {
      final fv = _parseD(_freightCtrl.text) ?? 0;
      if (_freightType == 'included' && fv > 1e-9) {
        out.add(
          'Freight is set to Included —” the freight value may not add to the line total. Use Separate if you need to add it.',
        );
      }
    }
    final q = _qtyVal();
    final sell = _ratesPerKgEconomics
        ? _sellingParsedAsPerKg()
        : _parseD(_sellingCtrl.text);
    if (q > 0 && sell != null && sell > 0) {
      final profit = _profitPreview();
      final lm = lineMoney(_currentLine(), taxMode: _taxMode);
      final threshold = math.max(50.0, lm * 0.01);
      if (profit < threshold) {
        out.add(
          'Profit looks unusually low after tax and charges —” check Tax % and rates.',
        );
      }
    }
    return out;
  }

  Widget _liveTotalsCard(ThemeData theme) {
    // Use the reliable focus-driven flag OR direct inset check.
    final kbd = _keyboardVisible || View.of(context).viewInsets.bottom > 0;
    final sell = _ratesPerKgEconomics
        ? _sellingParsedAsPerKg()
        : _parseD(_sellingCtrl.text);
    final profit = _profitPreview();
    final enteredPurchase = _ratesPerKgEconomics
        ? (_landingParsedAsPerKg() ?? 0)
        : (_parseD(_landingCtrl.text) ?? 0);
    final line = _currentLine();

    final warnings =
        _moreSectionExpanded ? _gstSoftWarningMessages() : const <String>[];
    final gst = lineTaxAmount(line, taxMode: _taxMode);
    final total = lineMoney(line, taxMode: _taxMode);

    if (kbd) {
      // In keyboard mode, we return an empty widget and move the logic to the unified footer row.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in warnings)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    w,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SheetSummaryPill(
                    label: 'QTY',
                    value: _qtyAndUnitWeightSummaryLine(),
                    color: const Color(0xFF64748B),
                  ),
                  SheetSummaryPill(
                    label: 'RATE',
                    value: _purchaseRateLabel(true)
                        .replaceFirst(' *', '')
                        .replaceFirst('Landing cost ', '')
                        .replaceFirst('Purchase Rate ', ''),
                    subtitle: formatRupee(enteredPurchase, decimals: true),
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SheetMetric(
                    label: 'TAX',
                    value: gst > 1e-6 ? formatRupee(gst, decimals: true) : '—”',
                    color: const Color(0xFF64748B),
                  ),
                  SheetMetric(
                    label: 'PROFIT',
                    value: sell != null && sell > 0
                        ? formatRupee(profit, decimals: true)
                        : '—”',
                    color: (profit >= 0)
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                  SheetMetric(
                    label: 'TOTAL',
                    value: formatRupee(total, decimals: true),
                    isBold: true,
                    color: const Color(0xFF0F172A),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildStockPreviewBar() {
    final id = _selectedCatalogItemId;
    if (id == null || id.isEmpty) return null;
    final stockAsync = ref.watch(stockItemDetailProvider(id));
    return stockAsync.when(
      loading: () => const SizedBox(
        height: 36,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (st) {
        final cur = _numD(st['current_stock']) ?? 0;
        final unit = (st['unit'] ?? _unitCtrl.text).toString().trim();
        final addQty = _parseD(_qtyCtrl.text) ?? 0;
        if (cur == 0 && addQty == 0) return const SizedBox.shrink();
        final after = cur + addQty;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: Color(0xFF2E7D32),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  addQty > 0
                      ? 'Stock now ${_fmtQty(cur)} $unit · after purchase ~${_fmtQty(after)} $unit'
                      : 'Stock now ${_fmtQty(cur)} $unit',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    if (widget.catalog.isEmpty && !widget.isEdit) {
      final loadingBody = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              'Loading catalog…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
      if (widget.fullPage) {
        return Scaffold(
          appBar: AppBar(title: const Text('Add item')),
          body: loadingBody,
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: loadingBody,
      );
    }

    final theme = Theme.of(context);
    final k = _kgPer();
    final cRow = _activeClassification();
    final showPerKgFields = _showPerKgLandingLabels;
    final showManualKgField =
        cRow.type == UnitType.weightBag && !_hasCatalogKg();
    final unitLow = _unitCtrl.text.trim().toLowerCase();
    // Compact, stable fields —” Tally-style density.
    final sheetTheme = theme.copyWith(visualDensity: VisualDensity.compact);

    const teal = Color(0xFF17A8A7);
    const ink = Color(0xFF0F172A);
    final gapField = widget.fullPage ? 12.0 : 6.0;
    final gapSection = widget.fullPage ? 16.0 : 8.0;
    final rateBasisSeg = _rateEntryBasisSegmented(k, showPerKgFields);

    final ratesAndGstChildren = <Widget>[
      if (rateBasisSeg != null) rateBasisSeg,
      _buildPurchaseSellingRateRow(
        showPerKgFields,
        preferVertical: false,
      ),
      SizedBox(height: widget.fullPage ? 10 : 8),
      _buildTaxModeChips(theme),
      SizedBox(height: widget.fullPage ? 10 : 8),
      ListenableBuilder(
        listenable: _lineTotalsListenable,
        builder: (ctx, _) {
          final l = _currentLine();
          final net = lineNetTaxableDecimal(l, taxMode: _taxMode).toDouble();
          final tax = lineTaxAmount(l, taxMode: _taxMode);
          final tot = lineMoney(l, taxMode: _taxMode);
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFAF9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF99F6E4)),
            ),
            child: Text(
              'Live preview · Net ${formatRupee(net, decimals: true)} · '
              'GST ${formatRupee(tax, decimals: true)} · '
              'Line total ${formatRupee(tot, decimals: true)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          );
        },
      ),
    ];

    final formChildren = <Widget>[
      if (!widget.fullPage) ...[
        Center(
          child: Container(
            width: 36,
            height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          widget.isEdit ? 'Edit line' : 'Add item',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Catalog, qty, rate first. Use Discount / Tax for HSN and bag rules.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.blueGrey[700],
            fontSize: 12,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
      ],
      KeyedSubtree(
        key: _itemKey,
        child: _fpShell(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PartyInlineSuggestField(
                  controller: _itemCtrl,
                  focusNode: _itemFocus,
                  focusAfterSelection: _qtyFocus,
                  debugLabel: 'catalogItem',
                  hintText: 'Search item (name, code, HSN)…',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                  idleOutlineColor: const Color(0xFF64748B),
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                  minQueryLength: 1,
                  maxMatches: 8,
                  dense: true,
                  minFieldHeight: widget.fullPage ? 52 : 0,
                  suggestionsAsOverlay: true,
                  items: _catalogSearchItems,
                  textInputAction: TextInputAction.next,
                  onSubmitted: () =>
                      FocusScope.of(context).requestFocus(_qtyFocus),
                  showAddRow: widget.navigateCatalogQuickAddItem != null,
                  addRowLabel: 'New catalog item…',
                  onAddRow: widget.navigateCatalogQuickAddItem == null
                      ? null
                      : () async {
                          final r = await widget.navigateCatalogQuickAddItem!();
                          if (r != null && mounted) {
                            final id = r['id']?.toString() ?? '';
                            final nm = r['name']?.toString() ?? '';
                            if (id.isNotEmpty) _onItemSelected(id, nm);
                          }
                        },
                  onSelected: (it) {
                    _onItemSelected(it.id, it.label);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Edit item name',
                icon: const Icon(Icons.edit_outlined, size: 22),
                visualDensity: VisualDensity.compact,
                onPressed: _focusItemNameField,
              ),
            ],
          ),
        ),
      ),
      if (_errItem != null)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(_errItem!,
              style: TextStyle(color: Colors.red[800], fontSize: 11)),
        ),
      if (_lastPurchaseAutofillHint != null &&
          _lastPurchaseAutofillHint!.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            _lastPurchaseAutofillHint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.blueGrey[700],
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
      if (_unitDetectHint != null && _unitDetectHint!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            _unitDetectHint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: teal,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      if (_selectedCatalogItemId != null &&
          _selectedCatalogItemId!.isNotEmpty) ...[
        SizedBox(height: gapField),
        ListenableBuilder(
          listenable: _qtyCtrl,
          builder: (context, _) {
            final bar = _buildStockPreviewBar();
            return bar ?? const SizedBox.shrink();
          },
        ),
      ],
      SizedBox(height: gapField),
      if (widget.fullPage)
        _fpShell(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: KeyedSubtree(
                  key: _qtyKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_qtyEntryModeSegmented() != null)
                        _qtyEntryModeSegmented()!,
                      TextField(
                        controller: _qtyCtrl,
                        focusNode: _qtyFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [_decimalFormatter(3)],
                        textInputAction: TextInputAction.next,
                        scrollPadding: _textFieldScrollPadding(),
                        decoration: _deco(_qtyFieldLabel(), errorText: _errQty),
                        onChanged: (_) {
                          _clearFieldErrors();
                          _schedulePreviewRebuild();
                        },
                        onSubmitted: (_) {
                          if (showManualKgField) {
                            FocusScope.of(context).requestFocus(_kgManualFocus);
                          } else {
                            FocusScope.of(context).requestFocus(_landingFocus);
                          }
                        },
                      ),
                      if (_kgEntryConversionHint() != null) ...[
                        SizedBox(height: gapField * 0.6),
                        _kgEntryConversionHint()!,
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: _unitKey,
                        child: (showPerKgFields && _hasCatalogKg())
                            ? InputDecorator(
                                decoration:
                                    _deco('Unit *', errorText: _errUnit),
                                child: Text(
                                  '${_unitCtrl.text.trim()} (${_fmtQty(k ?? 0)} kg)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : _unitDropdownField(errorText: _errUnit),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Unit, bags vs kg, and quantity —” tap to edit',
                      icon: const Icon(Icons.swap_vert_outlined, size: 22),
                      visualDensity: VisualDensity.compact,
                      onPressed: _focusQtyUnitEntry,
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: KeyedSubtree(
                key: _qtyKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_qtyEntryModeSegmented() != null)
                      _qtyEntryModeSegmented()!,
                    TextField(
                      controller: _qtyCtrl,
                      focusNode: _qtyFocus,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalFormatter(3)],
                      textInputAction: TextInputAction.next,
                      scrollPadding: _textFieldScrollPadding(),
                      decoration: _deco(_qtyFieldLabel(), errorText: _errQty),
                      onChanged: (_) {
                        _clearFieldErrors();
                        _schedulePreviewRebuild();
                      },
                      onSubmitted: (_) {
                        if (showManualKgField) {
                          FocusScope.of(context).requestFocus(_kgManualFocus);
                        } else {
                          FocusScope.of(context).requestFocus(_landingFocus);
                        }
                      },
                    ),
                    if (_kgEntryConversionHint() != null) ...[
                      SizedBox(height: gapField * 0.6),
                      _kgEntryConversionHint()!,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: _unitKey,
                      child: (showPerKgFields && _hasCatalogKg())
                          ? InputDecorator(
                              decoration: _deco('Unit *', errorText: _errUnit),
                              child: Text(
                                '${_unitCtrl.text.trim()} (${_fmtQty(k ?? 0)} kg)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : _unitDropdownField(errorText: _errUnit),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Unit, bags vs kg, and quantity —” tap to edit',
                    icon: const Icon(Icons.swap_vert_outlined, size: 22),
                    visualDensity: VisualDensity.compact,
                    onPressed: _focusQtyUnitEntry,
                  ),
                ],
              ),
            ),
          ],
        ),
      ListenableBuilder(
        listenable: _lineTotalsListenable,
        builder: (cx, _) {
          final chips = <Widget>[
            for (final w in [
              _catalogLooseKgMisconfigFixBanner(),
              _nameImpliesBagButKgUnitBanner(),
              _suggestOneBagInsteadOfKgBanner(),
              _didYouMeanKgNotBagsBanner(),
            ])
              if (w != null) w,
          ];
          if (chips.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.only(top: gapField * 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) SizedBox(height: gapField * 0.35),
                  chips[i],
                ],
              ],
            ),
          );
        },
      ),
      if (showManualKgField) ...[
        SizedBox(height: gapField),
        KeyedSubtree(
          key: _kgPerBagKey,
          child: TextField(
            controller: _kgPerBagCtrl,
            focusNode: _kgManualFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalFormatter(3)],
            textInputAction: TextInputAction.next,
            scrollPadding: _textFieldScrollPadding(),
            decoration: _deco('Kg per bag *', errorText: _errKgPerBag),
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(_landingFocus);
            },
          ),
        ),
      ],
      if (_PurchaseItemEntrySheetState._advancedInventoryEnabled && unitLow == 'box') ...[
        SizedBox(height: gapField),
        if (!(cRow.type == UnitType.singlePack ||
            cRow.type == UnitType.multiPackBox))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Fixed kg')),
                ButtonSegment(value: false, label: Text('Items/box')),
              ],
              selected: {_boxFixedWeight},
              onSelectionChanged: (s) {
                setState(() => _boxFixedWeight = s.first);
              },
            ),
          ),
        if (cRow.type == UnitType.multiPackBox)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemsPerBoxCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimalFormatter(3)],
                  decoration: _deco(
                    'Items per box *',
                    errorText: _errKgPerBag,
                  ),
                  onChanged: (_) => _schedulePreviewRebuild(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _weightPerItemCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_decimalFormatter(3)],
                  decoration: _deco(
                    'Kg per item',
                    errorText: _errKgPerBag,
                  ),
                  onChanged: (_) => _schedulePreviewRebuild(),
                ),
              ),
            ],
          )
        else if (cRow.type == UnitType.singlePack)
          TextField(
            controller: _kgPerBoxCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalFormatter(3)],
            decoration: _deco(
              'Kg per box',
              errorText: _errKgPerBag,
            ),
            onChanged: (_) => _schedulePreviewRebuild(),
          )
        else ...[
          if (_boxFixedWeight)
            TextField(
              controller: _kgPerBoxCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_decimalFormatter(3)],
              decoration: _deco('Kg per box *', errorText: _errKgPerBag),
              onChanged: (_) => _schedulePreviewRebuild(),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemsPerBoxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_decimalFormatter(3)],
                    decoration: _deco(
                      'Items per box *',
                      errorText: _errKgPerBag,
                    ),
                    onChanged: (_) => _schedulePreviewRebuild(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _weightPerItemCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_decimalFormatter(3)],
                    decoration: _deco(
                      'Kg per item *',
                      errorText: _errKgPerBag,
                    ),
                    onChanged: (_) => _schedulePreviewRebuild(),
                  ),
                ),
              ],
            ),
        ],
      ],
      if (_PurchaseItemEntrySheetState._advancedInventoryEnabled && unitLow == 'tin') ...[
        SizedBox(height: gapField),
        TextField(
          controller: _weightPerTinCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_decimalFormatter(3)],
          decoration: _deco('Weight per tin *', errorText: _errKgPerBag),
          onChanged: (_) => _schedulePreviewRebuild(),
        ),
      ],
      SizedBox(height: gapField),
      widget.fullPage
          ? _fpShell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: ratesAndGstChildren,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: ratesAndGstChildren,
            ),
      SizedBox(height: widget.fullPage ? gapSection : 2),
      KeyedSubtree(
        key: _taxKey,
        child: _fpShell(
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(
                    () => _moreSectionExpanded = !_moreSectionExpanded,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Advanced',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Icon(
                          _moreSectionExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_moreSectionExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.omitLineFreightDeliveredBilltyDiscount) ...[
                          TextField(
                            controller: _taxCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [_decimalFormatter(2)],
                            scrollPadding: _textFieldScrollPadding(),
                            decoration: _deco('Tax %'),
                            onChanged: (_) {
                              _clearFieldErrors();
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _lineNotesCtrl,
                            maxLines: 4,
                            minLines: 1,
                            scrollPadding: _textFieldScrollPadding(),
                            decoration: _deco('Notes'),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _discCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [_decimalFormatter(2)],
                                  scrollPadding: _textFieldScrollPadding(),
                                  decoration: _deco('Discount %'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _taxCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [_decimalFormatter(2)],
                                  scrollPadding: _textFieldScrollPadding(),
                                  decoration: _deco('Tax %'),
                                  onChanged: (_) {
                                    _clearFieldErrors();
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _freightCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [_decimalFormatter(2)],
                                  scrollPadding: _textFieldScrollPadding(),
                                  decoration: _deco('Freight value'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: InputDecorator(
                                  decoration: _deco('Freight type'),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _freightType,
                                      isExpanded: true,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'separate',
                                          child: Text('Separate'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'included',
                                          child: Text('Included'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => _freightType = v);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _deliveredCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [_decimalFormatter(2)],
                                  scrollPadding: _textFieldScrollPadding(),
                                  decoration: _deco('Delivered rate'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _billtyCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [_decimalFormatter(2)],
                                  scrollPadding: _textFieldScrollPadding(),
                                  decoration: _deco('Billty rate'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _lineNotesCtrl,
                            maxLines: 4,
                            minLines: 1,
                            scrollPadding: _textFieldScrollPadding(),
                            decoration: _deco('Notes'),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ListenableBuilder(
        listenable: _lineTotalsListenable,
        builder: (cx, _) {
          final showMeta = _showHsnFooterMeta();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errHsn != null) ...[
                const SizedBox(height: 2),
                Text(
                  _errHsn!,
                  style: TextStyle(
                    color: Colors.red[800],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else if (showMeta &&
                  _hsnCode != null &&
                  _hsnCode!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'HSN: ${_hsnCode!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey[800],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (showMeta && _itemCode != null && _itemCode!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Item code: ${_itemCode!}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.blueGrey[800],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          );
        },
      ),
      if (!widget.fullPage) ...[
        SizedBox(height: gapField),
        ListenableBuilder(
          listenable: _lineTotalsListenable,
          builder: (context, _) => _liveTotalsCard(theme),
        ),
      ],
    ];

    if (widget.fullPage) {
      final footerPad = const EdgeInsets.fromLTRB(0, 6, 0, 10);
      final footer = widget.isEdit
          ? Padding(
              padding: footerPad,
              child: FilledButton(
                onPressed: () => _commit(closeSheet: true),
                style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : Padding(
              padding: footerPad,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _commit(closeSheet: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: teal,
                        side: const BorderSide(color: teal),
                        minimumSize: const Size(double.infinity, 50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text('DONE +'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _commit(closeSheet: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: teal,
                        minimumSize: const Size(double.infinity, 50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text(
                        'SAVE LINE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

      return Theme(
        data: sheetTheme,
        child: PopScope(
          canPop: !_isDirtySheet(),
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await _confirmDiscardAndPop();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: ink,
              elevation: 0,
              title: Text(widget.isEdit ? 'Edit item' : 'Add item'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: _handleLeadingBack,
              ),
            ),
            body: LayoutBuilder(
              builder: (context, c) {
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final double previewBottomPad =
                    safeBottom > 0 ? safeBottom + 6.0 : 10.0;
                final kbd = _keyboardVisible ||
                    MediaQuery.viewInsetsOf(context).bottom > 20;

                final previewPinned = Material(
                  elevation: 8,
                  color: Colors.white,
                  shadowColor: Colors.black26,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      kbd ? 4 : 8,
                      12,
                      kbd ? 4 : previewBottomPad,
                    ),
                    child: kbd
                        ? _buildKeyboardAccessoryRow(theme)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListenableBuilder(
                                listenable: _lineTotalsListenable,
                                builder: (context, _) => RepaintBoundary(
                                  child: _fpShell(_liveTotalsCard(theme)),
                                ),
                              ),
                              footer,
                            ],
                          ),
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: KeyboardSafeFormViewport(
                        dismissKeyboardOnTap: true,
                        scrollController: _scrollController,
                        horizontalPadding: 16,
                        topPadding: 4,
                        bottomExtraInset: 8,
                        minFieldsHeight: 0,
                        fields: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: formChildren,
                        ),
                        footer: const SizedBox.shrink(),
                      ),
                    ),
                    previewPinned,
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    final footer = widget.isEdit
        ? FilledButton(
            onPressed: () => _commit(closeSheet: true),
            style: FilledButton.styleFrom(
              backgroundColor: teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        : Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _commit(closeSheet: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: teal,
                    side: const BorderSide(color: teal),
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: const Text(
                    'Add more',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _commit(closeSheet: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          );

    Widget content = Theme(
      data: sheetTheme,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: LayoutBuilder(
          builder: (context, c) {
            final homeBottomInset = MediaQuery.paddingOf(context).bottom;
            final kbd = _keyboardVisible ||
                MediaQuery.viewInsetsOf(context).bottom > 20;
            return KeyboardSafeFormViewport(
              dismissKeyboardOnTap: true,
              scrollController: _scrollController,
              horizontalPadding: 10,
              topPadding: 4,
              bottomExtraInset: kbd ? 10 : 80,
              minFieldsHeight: 0,
              fields: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: formChildren,
              ),
              footer: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                ),
                child: Material(
                  elevation: kbd ? 8 : 0,
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      kbd ? 4 : 8,
                      10,
                      kbd
                          ? 4
                          : (homeBottomInset > 0 ? homeBottomInset + 10.0 : 12.0),
                    ),
                    child: kbd ? _buildKeyboardAccessoryRow(theme) : footer,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    if (!widget.fullPage) {
      content = Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: content,
      );
    }

    return content;
  }

  Widget _buildKeyboardAccessoryRow(ThemeData theme) {
    return ListenableBuilder(
      listenable: _lineTotalsListenable,
      builder: (context, _) {
        final l = _currentLine();
        final t = lineMoney(l, taxMode: _taxMode);
        final p = _profitPreview();
        final s = _ratesPerKgEconomics
            ? _sellingParsedAsPerKg()
            : _parseD(_sellingCtrl.text);
        final qStr = _qtyAndUnitWeightSummaryLine();

        return Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TOTAL: ${formatRupee(t)}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A))),
                Row(
                  children: [
                    Text('PROFIT: ${s != null && s > 0 ? formatRupee(p) : "—”"}',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: p >= 0
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626))),
                    const SizedBox(width: 8),
                    Builder(builder: (context) {
                      final taxable =
                          lineNetTaxableDecimal(l, taxMode: _taxMode)
                              .toDouble();
                      final tax = lineTaxAmount(l, taxMode: _taxMode);
                      return Text(
                        'NET ${formatRupee(taxable)} · TAX ${formatRupee(tax)}',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B)),
                      );
                    }),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(qStr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B))),
            ),
            if (!widget.isEdit)
              SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: () => _commit(closeSheet: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF17A8A7),
                    side: const BorderSide(color: Color(0xFF17A8A7)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Add+'),
                ),
              ),
            if (!widget.isEdit) const SizedBox(width: 4),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: () => _commit(closeSheet: true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF17A8A7),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        );
      },
    );
  }
}
