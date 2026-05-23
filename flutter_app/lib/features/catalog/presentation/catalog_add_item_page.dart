import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/services/duplicate_detection_service.dart';
import '../../../core/services/smart_unit_service.dart';
import '../../../core/unit_engine/smart_validation_engine.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/form_feedback.dart';
import '../../../core/widgets/form_field_scroll.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/inline_search_field.dart';
import '../../../shared/widgets/keyboard_safe_form_viewport.dart';

const _kPrefLastCategory = 'catalog_last_category_id';
const _kPrefLastType = 'catalog_last_type_id';
const _kPrefLastSupplier = 'catalog_last_supplier_id';

const _kUnits = <String>['bag', 'box', 'kg', 'tin', 'piece'];

/// Add catalog item: category, subcategory, unit, defaults, at least one supplier.
class CatalogAddItemPage extends ConsumerStatefulWidget {
  const CatalogAddItemPage({
    super.key,
    required this.categoryId,
    required this.typeId,
    this.defaultSupplierId,
  });

  final String categoryId;
  final String typeId;
  /// Optional deep-link / query param — pre-selects a default supplier chip.
  final String? defaultSupplierId;

  @override
  ConsumerState<CatalogAddItemPage> createState() => _CatalogAddItemPageState();
}

class _CatalogAddItemPageState extends ConsumerState<CatalogAddItemPage> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _kg = TextEditingController();
  final _perBox = TextEditingController();
  final _perTin = TextEditingController();
  final _hsn = TextEditingController();
  final _itemCode = TextEditingController();
  final _tax = TextEditingController();
  final _supplierSearch = TextEditingController();

  String? _categoryId;
  String? _typeId;
  String? _unit;
  final _supplierIds = <String>[];

  bool _saving = false;
  bool _touched = false;
  int _step = 0;
  final _categoryAnchorKey = GlobalKey();
  final _typeAnchorKey = GlobalKey();
  String? _kgErr;
  String? _boxErr;
  String? _tinErr;

  CatalogDuplicateDebouncer? _dupDebouncer;
  List<Map<String, dynamic>> _fuzzyDupHits = const [];
  final Set<String> _dismissedDupIds = {};

  static const _fieldPad = EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  static InputBorder _fieldBorder(BuildContext context) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      );

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _typeId = widget.typeId;
    _dupDebouncer = CatalogDuplicateDebouncer(ref.read(hexaApiProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      await _offerResumeDraft();
      if (!mounted) return;
      await _applySavedDefaults();
    });
  }

  String get _activeDraftKey =>
      'catalog_draft_item_${_categoryId ?? widget.categoryId}_${_typeId ?? widget.typeId}';

  Future<void> _offerResumeDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_activeDraftKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    Map<String, dynamic>? m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {}
    if (m == null) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume item creation?'),
        content: const Text('You have an unsaved draft for this subcategory.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Discard')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (!mounted) return;
    if (go == true) {
      setState(() {
        _name.text = m!['name']?.toString() ?? '';
        final rawU = m['unit']?.toString().trim();
        _unit = (rawU != null && rawU.isNotEmpty) ? rawU.toLowerCase() : null;
        _kg.text = m['kg']?.toString() ?? '';
        _perBox.text = m['perBox']?.toString() ?? '';
        _perTin.text = m['perTin']?.toString() ?? '';
        _hsn.text = m['hsn']?.toString() ?? '';
        _itemCode.text = m['itemCode']?.toString() ?? '';
        _tax.text = m['tax']?.toString() ?? '';
        if (m['categoryId'] != null) _categoryId = m['categoryId']?.toString();
        if (m['typeId'] != null) _typeId = m['typeId']?.toString();
        if (m['supplierIds'] is List) {
          _supplierIds
            ..clear()
            ..addAll((m['supplierIds'] as List).map((e) => e.toString()));
        }
        _step = ((m['step'] as num?)?.toInt() ?? 0).clamp(0, 5);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    } else {
      await prefs.remove(_activeDraftKey);
    }
  }

  Future<void> _saveDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (_name.text.trim().isEmpty && _unit == null) {
      await prefs.remove(_activeDraftKey);
      return;
    }
    await prefs.setString(
      _activeDraftKey,
      jsonEncode({
        'name': _name.text,
        'unit': _unit,
        'kg': _kg.text,
        'perBox': _perBox.text,
        'perTin': _perTin.text,
        'hsn': _hsn.text,
        'itemCode': _itemCode.text,
        'tax': _tax.text,
        'categoryId': _categoryId,
        'typeId': _typeId,
        'supplierIds': _supplierIds,
        'step': _step,
      }),
    );
  }

  Future<void> _applySavedDefaults() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final param = widget.defaultSupplierId?.trim();
    final sid = (param != null && param.isNotEmpty)
        ? param
        : prefs.getString(_kPrefLastSupplier)?.trim();
    if (sid != null && sid.isNotEmpty && mounted) {
      setState(() {
        if (!_supplierIds.contains(sid)) _supplierIds.add(sid);
      });
    }
    final lc = prefs.getString(_kPrefLastCategory)?.trim();
    final lt = prefs.getString(_kPrefLastType)?.trim();
    if (lc != null && lc == widget.categoryId && lt != null && lt.isNotEmpty) {
      final types = await ref.read(categoryTypesListProvider(lc).future);
      if (!mounted) return;
      if (types.any((t) => t['id']?.toString() == lt)) {
        setState(() => _typeId = lt);
      }
    }
  }

  void _scheduleDupCheck() {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    _dupDebouncer?.schedule(
      businessId: session.primaryBusiness.id,
      name: _name.text,
      supplierId: _supplierIds.isNotEmpty ? _supplierIds.first : null,
      categoryId: _categoryId,
      typeId: _typeId,
      onResult: (hits) {
        if (!mounted) return;
        setState(() => _fuzzyDupHits = hits);
      },
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _kg.dispose();
    _perBox.dispose();
    _perTin.dispose();
    _hsn.dispose();
    _itemCode.dispose();
    _tax.dispose();
    _supplierSearch.dispose();
    _dupDebouncer?.dispose();
    super.dispose();
  }

  String? _nameFromRows(List<Map<String, dynamic>> rows, String? id) {
    if (id == null) return null;
    for (final r in rows) {
      if (r['id']?.toString() == id) return r['name']?.toString();
    }
    return null;
  }

  Future<void> _pickCategorySheet(List<Map<String, dynamic>> cl) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: SizedBox(
            height: math.min(
              420.0,
              MediaQuery.sizeOf(ctx).height * 0.55,
            ),
            child: ListView(
              shrinkWrap: false,
              children: [
                for (final c in cl)
                  ListTile(
                    title: Text(c['name']?.toString() ?? ''),
                    onTap: () => ctx.pop(c['id']?.toString()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (id != null) _onCategoryChanged(id);
  }

  Future<void> _pickTypeSheet(List<Map<String, dynamic>> tl) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: SizedBox(
            height: math.min(
              420.0,
              MediaQuery.sizeOf(ctx).height * 0.55,
            ),
            child: ListView(
              shrinkWrap: false,
              children: [
                for (final t in tl)
                  ListTile(
                    title: Text(t['name']?.toString() ?? ''),
                    onTap: () => ctx.pop(t['id']?.toString()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (id != null) setState(() => _typeId = id);
    _scheduleDupCheck();
  }

  bool get _isValid {
    if (_categoryId == null || _typeId == null) return false;
    if (_name.text.trim().isEmpty) return false;
    if (_unit == null || _unit!.isEmpty) return false;
    if (_supplierIds.isEmpty) return false;
    if (_unit == 'bag' && parseOptionalKgPerBag(_kg.text) == null) return false;
    if (_unit == 'box') {
      final v = double.tryParse(_perBox.text.trim());
      if (v == null || v <= 0) return false;
    }
    if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      final w = double.tryParse(_perTin.text.trim());
      if (w == null || w <= 0) return false;
    }
    return true;
  }

  String? _existingItemIdFrom409(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final d = e.response?.data;
    if (d is Map && d['detail'] is Map) {
      return (d['detail'] as Map)['existing_item_id']?.toString();
    }
    return null;
  }

  Future<void> _create() async {
    if (!_isValid) {
      setState(() => _touched = true);
      if (_categoryId == null || _typeId == null) {
        await ensureFormFieldVisible(_categoryAnchorKey);
      } else if (_name.text.trim().isEmpty) {
        _nameFocus.requestFocus();
      }
      return;
    }
    if (_unit == 'bag') {
      final kg = parseOptionalKgPerBag(_kg.text);
      if (kg == null) {
        setState(() => _kgErr = 'Enter kg per bag (must be > 0)');
        return;
      }
    }
    if (_unit == 'box') {
      final v = double.tryParse(_perBox.text.trim());
      if (v == null || v <= 0) {
        setState(() => _boxErr = 'Items per box must be > 0');
        return;
      }
    }
    if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      final w = double.tryParse(_perTin.text.trim());
      if (w == null || w <= 0) {
        setState(() => _tinErr = 'Weight must be > 0');
        return;
      }
    }
    final taxRaw = _tax.text.trim();
    double? taxPct;
    if (taxRaw.isNotEmpty) {
      taxPct = double.tryParse(taxRaw);
      if (taxPct == null || taxPct < 0 || taxPct > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tax % must be between 0 and 100')),
          );
        }
        return;
      }
    }
    final hsn = _hsn.text.trim();
    final ic = _itemCode.text.trim();
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final name = _name.text.trim();
    final hits = await ref.read(hexaApiProvider).catalogFuzzyCheck(
          businessId: session.primaryBusiness.id,
          name: name,
          categoryId: _categoryId,
          typeId: _typeId,
        );
    final exact = hits.where((h) {
      return h['name']?.toString().trim().toLowerCase() ==
          name.toLowerCase();
    }).toList();
    if (exact.isNotEmpty && mounted) {
      final first = exact.first;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Similar item already exists'),
          content: Text(
            'Found: "${first['name']?.toString() ?? name}" in this category.\n'
            'Create a separate item anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Use existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create new anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        final id = first['id']?.toString();
        if (id != null && id.isNotEmpty && mounted) {
          context.push('/catalog/item/$id');
        }
        return;
      }
    }
    setState(() => _saving = true);
    final tinW = _unit == 'tin' && _perTin.text.trim().isNotEmpty
        ? double.tryParse(_perTin.text.trim())
        : null;
    try {
      final created = await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: _categoryId!,
            typeId: _typeId,
            name: name,
            defaultUnit: _unit!,
            defaultSupplierIds: List<String>.from(_supplierIds),
            defaultBrokerIds: const [],
            hsnCode: hsn.isEmpty ? null : hsn,
            itemCode: ic.isEmpty ? null : ic,
            taxPercent: taxPct,
            defaultPurchaseUnit: _unit,
            defaultKgPerBag: _unit == 'bag' ? parseOptionalKgPerBag(_kg.text) : null,
            defaultItemsPerBox: _unit == 'box' ? double.tryParse(_perBox.text.trim()) : null,
            defaultWeightPerTin: (tinW != null && tinW > 0) ? tinW : null,
          );
      final nid = created['id']?.toString() ?? '';
      await ref.read(sharedPreferencesProvider).remove(_activeDraftKey);
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kPrefLastCategory, _categoryId!);
      await prefs.setString(_kPrefLastType, _typeId!);
      if (_supplierIds.isNotEmpty) {
        await prefs.setString(_kPrefLastSupplier, _supplierIds.first);
      }
      ref.invalidate(catalogItemsListProvider);
      invalidateBusinessAggregates(ref);
      if (mounted) {
        final code = created['item_code']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_name.text.trim()} created${code.isNotEmpty ? ' · $code' : ''}',
            ),
            action: nid.isNotEmpty
                ? SnackBarAction(
                    label: 'Print label',
                    onPressed: () => context.push(
                      '/barcode/print/${Uri.encodeComponent(nid)}',
                    ),
                  )
                : null,
          ),
        );
        context.pop(<String, dynamic>{'id': nid, 'name': _name.text.trim()});
      }
    } on DioException catch (e) {
      final existing = _existingItemIdFrom409(e);
      if (existing != null && mounted) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar item exists'),
            content: const Text('Open the existing catalog item?'),
            actions: [
              TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => ctx.pop(true), child: const Text('Open')),
            ],
          ),
        );
        if (open == true) {
          if (!mounted) return;
          context.pop(false);
          if (!mounted) return;
          context.push('/catalog/item/$existing');
        }
        return;
      }
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Widget> _reviewLines(
    BuildContext context, {
    required List<Map<String, dynamic>> supplierRows,
  }) {
    final tt = Theme.of(context).textTheme;
    final name = _name.text.trim().isEmpty ? '—' : _name.text.trim();
    final u = _unit == null ? '—' : _unit!.toUpperCase();
    String unitDetail;
    if (_unit == 'bag') {
      final kg = _kg.text.trim().isEmpty ? '—' : _kg.text.trim();
      unitDetail = '$u · $kg kg/bag';
    } else if (_unit == 'box') {
      final pb = _perBox.text.trim().isEmpty ? '—' : _perBox.text.trim();
      unitDetail = '$u · $pb items/box';
    } else if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
      unitDetail = '$u · ${_perTin.text.trim()} / tin';
    } else {
      unitDetail = u;
    }
    final supNames = _supplierIds
        .map((id) {
          for (final s in supplierRows) {
            if (s['id']?.toString() == id) {
              return s['name']?.toString() ?? id;
            }
          }
          return id;
        })
        .toList();
    final code = _itemCode.text.trim();
    final hsn = _hsn.text.trim();
    final tax = _tax.text.trim();
    return [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: name,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            TextSpan(
              text: ' · $unitDetail',
              style: tt.bodySmall?.copyWith(
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      if (code.isNotEmpty || hsn.isNotEmpty || tax.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          [
            if (code.isNotEmpty) 'Code: $code',
            if (hsn.isNotEmpty) 'HSN: $hsn',
            if (tax.isNotEmpty) 'Tax: $tax%',
          ].join('  ·  '),
          style: tt.bodySmall?.copyWith(
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (supNames.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'Suppliers: ${supNames.join(', ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.bodySmall?.copyWith(color: const Color(0xFF64748B)),
        ),
      ],
    ];
  }

  Future<void> _onCategoryChanged(String? cid) async {
    if (cid == null) return;
    setState(() {
      _categoryId = cid;
      _typeId = null;
    });
    final types = await ref.read(categoryTypesListProvider(cid).future);
    if (!mounted) return;
    if (types.isNotEmpty) {
      setState(() => _typeId = types.first['id']?.toString());
    }
    _scheduleDupCheck();
  }

  Widget _supplierChips(List<Map<String, dynamic>> allRows) {
    final nameById = {
      for (final s in allRows)
        if ((s['id']?.toString() ?? '').isNotEmpty)
          s['id'].toString(): s['name']?.toString() ?? '',
    };
    if (_supplierIds.isEmpty) {
      return Text(
        'Required — add at least one supplier who sells this item.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _touched && _supplierIds.isEmpty
                  ? HexaColors.loss
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in _supplierIds)
          InputChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                nameById[id] ?? id,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            onDeleted: () => setState(() => _supplierIds.remove(id)),
          ),
      ],
    );
  }

  List<InlineSearchItem> _supplierPickItems(List<Map<String, dynamic>> list) {
    return [
      for (final s in list)
        if (!_supplierIds.contains(s['id']?.toString()))
          InlineSearchItem(
            id: s['id']?.toString() ?? '',
            label: s['name']?.toString() ?? 'Supplier',
            subtitle: (s['phone']?.toString() ?? '').trim().isEmpty
                ? null
                : s['phone']?.toString(),
          ),
    ];
  }

  bool _canAdvanceFromStep() {
    switch (_step) {
      case 0:
        return _categoryId != null && _typeId != null;
      case 1:
        return _name.text.trim().isNotEmpty && _unit != null && _unit!.isNotEmpty;
      case 2:
        if (_unit == 'bag') {
          return parseOptionalKgPerBag(_kg.text) != null;
        }
        if (_unit == 'box') {
          final v = double.tryParse(_perBox.text.trim());
          return v != null && v > 0;
        }
        if (_unit == 'tin' && _perTin.text.trim().isNotEmpty) {
          final w = double.tryParse(_perTin.text.trim());
          return w != null && w > 0;
        }
        return true;
      case 3:
        return _supplierIds.isNotEmpty;
      case 4:
        return true;
      default:
        return _isValid;
    }
  }

  void _goNext() {
    setState(() => _touched = true);
    if (!_canAdvanceFromStep()) {
      if (_step == 0) {
        unawaited(ensureFormFieldVisible(_categoryAnchorKey));
      } else if (_step == 1) {
        _nameFocus.requestFocus();
      }
      return;
    }
    if (_step < 5) {
      unawaited(_saveDraft());
      setState(() => _step += 1);
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(itemCategoriesListProvider);
    final typesAsync = _categoryId != null
        ? ref.watch(categoryTypesListProvider(_categoryId!))
        : null;

    final typeName = typesAsync?.maybeWhen(
          data: (types) {
            for (final t in types) {
              if (t['id']?.toString() == _typeId) {
                return t['name']?.toString() ?? '';
              }
            }
            return '';
          },
          orElse: () => '',
        ) ??
        '';

    final dupAlerts = _fuzzyDupHits
        .where((h) =>
            fuzzyHitScore(h) >= 0.75 &&
            !_dismissedDupIds.contains(h['id']?.toString() ?? ''))
        .toList();

    final nameErr = _touched && _name.text.trim().isEmpty;
    final unitErr = _touched && (_unit == null || _unit!.isEmpty);
    final supErr = _touched && _supplierIds.isEmpty;
    final supRows = ref.watch(suppliersListProvider).maybeWhen(
          data: (raw) => raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          orElse: () => <Map<String, dynamic>>[],
        );
    final detectedUnit = SmartValidationEngine.detectUnitFromName(_name.text);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveDraft();
        if (!mounted) return;
        context.pop(false);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New item'),
              Text(
                'Step ${_step + 1} of 6',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving
                ? null
                : () async {
                    await _saveDraft();
                    if (!mounted) return;
                    context.pop(false);
                  },
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, cts) {
                final minFields = math.max(240.0, cts.maxHeight - 280);
                return KeyboardSafeFormViewport(
                  dismissKeyboardOnTap: false,
                  horizontalPadding: 16,
                  topPadding: 8,
                  minFieldsHeight:
                      cts.hasBoundedHeight ? minFields : 240,
                  fields: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
              if (_step == 0) ...[
              Text('Category & subcategory', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              categoriesAsync.when(
                skipLoadingOnReload: true,
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Could not load categories'),
                data: (cats) {
                  final cl = cats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                  final label = _nameFromRows(cl, _categoryId) ?? 'Choose category';
                  return KeyedSubtree(
                    key: _categoryAnchorKey,
                    child: InkWell(
                      onTap: () => unawaited(_pickCategorySheet(cl)),
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Category',
                          contentPadding: _fieldPad,
                          border: _fieldBorder(context),
                          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (typesAsync != null)
                typesAsync.when(
                  skipLoadingOnReload: true,
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Could not load subcategories'),
                  data: (types) {
                    final tl = types.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                    final inList = _typeId != null &&
                        tl.any((t) => t['id']?.toString() == _typeId);
                    final tid = inList
                        ? _typeId
                        : tl.first['id']?.toString();
                    if (tid != null && tid != _typeId) {
                      scheduleMicrotask(() {
                        if (mounted) setState(() => _typeId = tid);
                      });
                    }
                    if (tl.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No subcategory (type) for this category yet. Add a type in Catalog for this category, then you can add products here.',
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _categoryId == null
                                  ? null
                                  : () => context.push('/catalog/category/$_categoryId'),
                              child: const Text('Open this category in Catalog'),
                            ),
                          ],
                        ),
                      );
                    }
                    final tlabel = _nameFromRows(tl, tid) ?? 'Choose subcategory';
                    return KeyedSubtree(
                      key: _typeAnchorKey,
                      child: InkWell(
                        onTap: () => unawaited(_pickTypeSheet(tl)),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Subcategory (type)',
                            contentPadding: _fieldPad,
                            border: _fieldBorder(context),
                            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                          ),
                          child: Text(
                            tlabel,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (typeName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  typeName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              ],
              if (_step == 1) ...[
              Text('Name & unit', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                focusNode: _nameFocus,
                autofocus: _step == 1,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Item name',
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                  errorText: nameErr ? 'Required' : null,
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: HexaColors.loss, width: 1.5),
                  ),
                ),
                onChanged: (_) {
                  _dismissedDupIds.clear();
                  setState(() {});
                  _scheduleDupCheck();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _itemCode,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Item code',
                  hintText: 'e.g. ITM-0023 (auto-assigned if blank)',
                  helperText: 'A barcode will be auto-generated from this code',
                  helperStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(
                        _itemCode.text.trim().isEmpty ? 'AUTO' : 'CUSTOM',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (detectedUnit != null &&
                  detectedUnit.isNotEmpty &&
                  (_unit == null || _unit != detectedUnit)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      SmartUnitService.detectFromName(_name.text)?.label ??
                          'Use detected unit: ${detectedUnit.toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => setState(() {
                      _unit = detectedUnit;
                      _kgErr = null;
                      _boxErr = null;
                      _tinErr = null;
                    }),
                  ),
                ),
              ],
              if (_name.text.trim().length >= 2 && dupAlerts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Material(
                  color: const Color(0xFFFEF9C3),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Possible duplicate in catalog',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF854D0E),
                              ),
                        ),
                        for (final h in dupAlerts)
                          Text(
                            '· ${h['name']?.toString() ?? ''} (${(fuzzyHitScore(h) * 100).round()}% match)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () {
                                final id = dupAlerts.first['id']?.toString();
                                if (id == null || id.isEmpty) return;
                                context.push('/catalog/item/$id');
                              },
                              child: const Text('Use existing'),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                for (final h in dupAlerts) {
                                  final id = h['id']?.toString();
                                  if (id != null && id.isNotEmpty) {
                                    _dismissedDupIds.add(id);
                                  }
                                }
                              }),
                              child: const Text('Ignore, create new'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Unit type', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _kUnits)
                    ChoiceChip(
                      label: Text(u.toUpperCase()),
                      selected: _unit == u,
                      onSelected: (_) => setState(() {
                        _unit = u; // _kUnits are lowercase — keeps review + chips in sync
                        _kgErr = null;
                        _boxErr = null;
                        _tinErr = null;
                      }),
                    ),
                ],
                ),
              if (unitErr)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Select a unit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HexaColors.loss),
                  ),
                ),
              ],
              if (_step == 2) ...[
              Text('Unit configuration', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              if (_unit == 'bag') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _kg,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Weight per bag (kg)',
                    hintText: 'e.g. 50',
                    errorText: _kgErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_kgErr != null) setState(() => _kgErr = null);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                BagDefaultUnitHint(
                  kgAlreadySet: () {
                    final v = parseOptionalKgPerBag(_kg.text);
                    return v != null && v > 0;
                  }(),
                ),
              ],
              if (_unit == 'box') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _perBox,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Items per box',
                    errorText: _boxErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_boxErr != null) setState(() => _boxErr = null);
                    setState(() {});
                  },
                ),
              ],
              if (_unit == 'tin') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _perTin,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Weight per tin (optional)',
                    errorText: _tinErr,
                    contentPadding: _fieldPad,
                    border: _fieldBorder(context),
                    enabledBorder: _fieldBorder(context),
                  ),
                  onChanged: (_) {
                    if (_tinErr != null) setState(() => _tinErr = null);
                    setState(() {});
                  },
                ),
              ],
              if (_unit != null &&
                  _unit != 'bag' &&
                  _unit != 'box' &&
                  _unit != 'tin')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'No extra defaults for ${_unit!.toUpperCase()}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
              if (_step == 3) ...[
              Text('Default suppliers *', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 4),
              if (supErr)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Add at least one supplier',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HexaColors.loss),
                  ),
                ),
              ref.watch(suppliersListProvider).when(
                    skipLoadingOnReload: true,
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Could not load suppliers'),
                    data: (rows) {
                      final list =
                          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                      if (list.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No suppliers yet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => context.push('/contacts'),
                              icon: const Icon(Icons.group_add_outlined, size: 20),
                              label: const Text('Open Contacts to add a supplier'),
                            ),
                          ],
                        );
                      }
                      final pick = _supplierPickItems(list);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _supplierChips(list),
                          const SizedBox(height: 6),
                          if (pick.isNotEmpty) ...[
                            Text(
                              'Search and pick supplier (name or phone)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            InlineSearchField(
                              key: ValueKey('sup_srch_${_supplierIds.length}'),
                              items: pick,
                              controller: _supplierSearch,
                              placeholder: 'Type to search…',
                              minQueryLength: 1,
                              onSelected: (it) {
                                setState(() {
                                  if (it.id.isNotEmpty && !_supplierIds.contains(it.id)) {
                                    _supplierIds.add(it.id);
                                  }
                                  _supplierSearch.clear();
                                });
                                _scheduleDupCheck();
                              },
                            ),
                          ] else
                            Text(
                              _supplierIds.isEmpty
                                  ? '—'
                                  : 'All available suppliers are already added',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      );
                    },
                  ),
              ],
              if (_step == 4) ...[
              Text('Product code, HSN & tax', style: HexaDsType.formSectionLabel),
              const SizedBox(height: 6),
              Text(
                'Match your price list: code, hsn, tax_rate (optional).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _itemCode,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Product / item code (optional)',
                  hintText: 'e.g. 2104',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hsn,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'HSN / SAC (optional)',
                  hintText: 'e.g. 11010000',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Default tax % (optional, GST)',
                  hintText: 'e.g. 5 or 0',
                  contentPadding: _fieldPad,
                  border: _fieldBorder(context),
                  enabledBorder: _fieldBorder(context),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onChanged: (_) => setState(() {}),
              ),
              ],
              if (_step == 5) ...[
                Text('Review', style: HexaDsType.formSectionLabel),
                const SizedBox(height: 6),
                ..._reviewLines(
                  context,
                  supplierRows: supRows,
                ),
                const SizedBox(height: 2),
                Text(
                  'Unit prices are set on each purchase.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
                  footer: Material(
          color: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
          elevation: 2,
                        child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _step < 5
                  ? Row(
                      children: [
                        if (_step > 0)
                          TextButton(
                            onPressed: _goBack,
                            child: const Text('Back'),
                          ),
                        if (_step > 0) const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _goNext,
                            child: Text(
                              _canAdvanceFromStep() ? 'Next' : 'Fill required fields',
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: _goBack,
                              child: const Text('Back'),
                            ),
                            const Spacer(),
                            Text(
                              'Step 6 of 6',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FilledButton(
                          onPressed: (_saving || !_isValid) ? null : _create,
                          style: FilledButton.styleFrom(
                            disabledBackgroundColor: HexaColors.brandDisabledBg,
                            disabledForegroundColor: HexaColors.brandDisabledText,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isValid ? 'Create item' : 'Complete required fields'),
                        ),
                      ],
                    ),
            ),
                     ),
                     );
                  },
                ),
          ),
        ),
      ),
    );
  }
}
