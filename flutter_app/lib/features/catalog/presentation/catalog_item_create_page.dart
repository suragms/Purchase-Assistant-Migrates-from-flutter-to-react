import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/navigation_ext.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/stock_providers.dart' show bulkStockListProvider;
import '../../../core/unit_engine/stock_tracking_profile.dart';
import '../../../core/widgets/async_value_form.dart';
import '../../../shared/widgets/inline_search_field.dart';
import '../../../shared/widgets/packaging_type_selector.dart';
import '../catalog_create_prefs.dart';

/// Simple catalog item create — subcategory, name, unit type, optional more fields.
class CatalogItemCreatePage extends ConsumerStatefulWidget {
  const CatalogItemCreatePage({
    super.key,
    this.defaultSupplierId,
    this.defaultBrokerId,
    this.presetCategoryId,
    this.presetTypeId,
    this.returnResultOnSave = false,
  });

  final String? defaultSupplierId;
  final String? defaultBrokerId;
  final String? presetCategoryId;
  final String? presetTypeId;
  final bool returnResultOnSave;

  @override
  ConsumerState<CatalogItemCreatePage> createState() =>
      _CatalogItemCreatePageState();
}

/// @deprecated Use [CatalogItemCreatePage].
typedef QuickAddCatalogItemPage = CatalogItemCreatePage;

class _CatalogItemCreatePageState extends ConsumerState<CatalogItemCreatePage> {
  final _nameCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  final _ipbCtrl = TextEditingController();
  final _wptCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _purchaseRateCtrl = TextEditingController();
  final _sellingRateCtrl = TextEditingController();
  final _typeSearchCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _brokerSearchCtrl = TextEditingController();

  String? _typeId;
  String? _supplierId;
  String? _brokerId;
  String _packagingMode = StockTrackingMode.looseKg;
  bool _saving = false;
  String? _error;
  bool _prefilled = false;
  Timer? _nameDebounce;
  String? _bagDetectHint;
  bool _bagDetectDismissed = false;
  String? _kgFieldError;
  String? _ipbFieldError;
  bool _selectingType = false;

  static final _kgInName =
      RegExp(r'(\d+(?:\.\d+)?)\s*kg', caseSensitive: false);
  static final _boxInName =
      RegExp(r'\b(?:box|ctn)\b', caseSensitive: false);

  String _packageTypeForMode(String mode) {
    switch (mode) {
      case StockTrackingMode.wholesaleBag:
        return 'SACK';
      case StockTrackingMode.looseKg:
        return 'LOOSE';
      case StockTrackingMode.box:
        return 'BOX';
      case StockTrackingMode.tin:
        return 'TIN';
      case StockTrackingMode.piece:
        return 'PIECE';
      case StockTrackingMode.retailPacket:
      default:
        return 'RETAIL_PACKET';
    }
  }

  bool get _modeUsesWeightField =>
      _packagingMode == StockTrackingMode.wholesaleBag ||
      _packagingMode == StockTrackingMode.retailPacket;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _kgCtrl.addListener(_onKgChanged);
    _typeSearchCtrl.addListener(_onTypeSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedParty());
  }

  void _onTypeSearchChanged() {
    if (_selectingType) return;
    if (_typeId == null) return;
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    final row = _rowByTypeId(types, _typeId!);
    if (row == null) {
      setState(() => _typeId = null);
      return;
    }
    final picked = row['name']?.toString().trim().toLowerCase() ?? '';
    final typed = _typeSearchCtrl.text.trim().toLowerCase();
    if (picked != typed) {
      setState(() => _typeId = null);
    }
  }

  Future<void> _loadSavedParty() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (widget.defaultSupplierId != null &&
        widget.defaultSupplierId!.isNotEmpty) {
      return;
    }
    if (widget.defaultBrokerId != null && widget.defaultBrokerId!.isNotEmpty) {
      return;
    }
    final sups = ref.read(suppliersListProvider).valueOrNull;
    final brokers = ref.read(brokersListProvider).valueOrNull;
    if (sups == null || brokers == null) return;

    final saved = await CatalogCreatePrefs.load(session.primaryBusiness.id);
    if (!mounted) return;
    var changed = false;
    if (_supplierId == null &&
        saved.supplierId != null &&
        saved.supplierId!.isNotEmpty) {
      for (final s in sups) {
        if (s['id']?.toString() == saved.supplierId) {
          _supplierId = saved.supplierId;
          _supplierSearchCtrl.text = s['name']?.toString() ?? '';
          changed = true;
          break;
        }
      }
    }
    if (_brokerId == null &&
        saved.brokerId != null &&
        saved.brokerId!.isNotEmpty) {
      for (final b in brokers) {
        if (b['id']?.toString() == saved.brokerId) {
          _brokerId = saved.brokerId;
          _brokerSearchCtrl.text = b['name']?.toString() ?? '';
          changed = true;
          break;
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _onKgChanged() {
    if (!mounted) return;
    if (_kgFieldError != null) {
      setState(() => _kgFieldError = null);
    }
  }

  void _onNameChanged() {
    _nameDebounce?.cancel();
    _nameDebounce =
        Timer(const Duration(milliseconds: 300), _applyBagDetectionFromName);
  }

  void _applyBagDetectionFromName() {
    if (!mounted || _bagDetectDismissed) return;
    final name = _nameCtrl.text;
    final kgMatch = _kgInName.firstMatch(name);
    if (kgMatch != null) {
      final kg = kgMatch.group(1) ?? '';
      if (kg.isNotEmpty) {
        setState(() {
          _packagingMode = StockTrackingMode.wholesaleBag;
          if (_kgCtrl.text.trim().isEmpty) {
            _kgCtrl.text = kg;
          }
          _bagDetectHint = 'Detected: $kg kg/bag ✓';
          _kgFieldError = null;
        });
        return;
      }
    }
    if (_boxInName.hasMatch(name)) {
      setState(() {
        _packagingMode = StockTrackingMode.box;
        if (_ipbCtrl.text.trim().isEmpty) {
          _ipbCtrl.text = '1';
        }
        _bagDetectHint = 'Default: 1 box = 1 unit';
        _ipbFieldError = null;
      });
      return;
    }
    if (_bagDetectHint != null) {
      setState(() => _bagDetectHint = null);
    }
  }

  void _dismissBagDetection() {
    setState(() {
      _bagDetectDismissed = true;
      _bagDetectHint = null;
    });
  }

  void _onPackagingModeChanged(String mode) {
    setState(() {
      final wasWeight = _modeUsesWeightField;
      _packagingMode = mode;
      final isWeight = mode == StockTrackingMode.wholesaleBag ||
          mode == StockTrackingMode.retailPacket;
      if (wasWeight && !isWeight) {
        _kgCtrl.clear();
        _kgFieldError = null;
      }
      if (mode == StockTrackingMode.box &&
          _ipbCtrl.text.trim().isEmpty &&
          _boxInName.hasMatch(_nameCtrl.text)) {
        _ipbCtrl.text = '1';
        _bagDetectHint = 'Default: 1 box = 1 unit';
      }
      if (mode == StockTrackingMode.wholesaleBag) {
        final m = _kgInName.firstMatch(_nameCtrl.text);
        if (m != null && _kgCtrl.text.trim().isEmpty) {
          _kgCtrl.text = m.group(1) ?? '';
          _bagDetectHint = 'Detected: ${_kgCtrl.text} kg/bag ✓';
        }
      }
      _bagDetectDismissed = true;
      if (mode != StockTrackingMode.box &&
          mode != StockTrackingMode.wholesaleBag) {
        _bagDetectHint = null;
      }
    });
  }

  double? _parsedKg() {
    final v = double.tryParse(_kgCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _nameCtrl.removeListener(_onNameChanged);
    _kgCtrl.removeListener(_onKgChanged);
    _typeSearchCtrl.removeListener(_onTypeSearchChanged);
    _nameCtrl.dispose();
    _kgCtrl.dispose();
    _ipbCtrl.dispose();
    _wptCtrl.dispose();
    _hsnCtrl.dispose();
    _purchaseRateCtrl.dispose();
    _sellingRateCtrl.dispose();
    _typeSearchCtrl.dispose();
    _supplierSearchCtrl.dispose();
    _brokerSearchCtrl.dispose();
    super.dispose();
  }

  void _maybePrefill(
    List<Map<String, dynamic>> types,
    List<Map<String, dynamic>> sups,
    List<Map<String, dynamic>> brokers,
  ) {
    if (_prefilled) return;
    _prefilled = true;
    if (widget.defaultSupplierId != null &&
        widget.defaultSupplierId!.isNotEmpty) {
      for (final s in sups) {
        if (s['id']?.toString() == widget.defaultSupplierId) {
          _supplierId = widget.defaultSupplierId;
          _supplierSearchCtrl.text = s['name']?.toString() ?? '';
          break;
        }
      }
    }
    if (widget.defaultBrokerId != null && widget.defaultBrokerId!.isNotEmpty) {
      for (final b in brokers) {
        if (b['id']?.toString() == widget.defaultBrokerId) {
          _brokerId = widget.defaultBrokerId;
          _brokerSearchCtrl.text = b['name']?.toString() ?? '';
          break;
        }
      }
    }
    if (_supplierId == null &&
        _supplierSearchCtrl.text.isEmpty &&
        sups.length == 1) {
      _supplierId = sups.first['id']?.toString();
      _supplierSearchCtrl.text = sups.first['name']?.toString() ?? '';
    }
    final presetType = widget.presetTypeId;
    if (presetType != null && presetType.isNotEmpty) {
      final row = _rowByTypeId(types, presetType);
      if (row != null) {
        _typeId = presetType;
        _typeSearchCtrl.text = row['name']?.toString() ?? '';
      }
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? _rowByTypeId(
    List<Map<String, dynamic>> types,
    String typeId,
  ) {
    for (final m in types) {
      if (m['id']?.toString() == typeId) return m;
    }
    return null;
  }

  List<InlineSearchItem> _typeItems(List<Map<String, dynamic>> types) {
    return [
      for (final m in types)
        InlineSearchItem(
          id: m['id']?.toString() ?? '',
          label: m['name']?.toString() ?? '—',
          subtitle: m['category_name']?.toString(),
          searchText:
              '${m['name'] ?? ''} ${m['category_name'] ?? ''}'.toLowerCase(),
        ),
    ];
  }

  List<InlineSearchItem> _supplierItems(List<Map<String, dynamic>> rows) {
    return [
      for (final s in rows)
        InlineSearchItem(
          id: s['id']?.toString() ?? '',
          label: s['name']?.toString() ?? '—',
          searchText: (s['name']?.toString() ?? '').toLowerCase(),
        ),
    ];
  }

  List<InlineSearchItem> _brokerItems(List<Map<String, dynamic>> rows) {
    return [
      for (final b in rows)
        InlineSearchItem(
          id: b['id']?.toString() ?? '',
          label: b['name']?.toString() ?? '—',
          subtitle: (b['phone']?.toString() ?? '').trim().isEmpty
              ? null
              : b['phone']?.toString(),
          searchText:
              '${b['name'] ?? ''} ${b['phone'] ?? ''}'.toLowerCase(),
        ),
    ];
  }

  bool _validate() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Item name is required.');
      return false;
    }
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    if (_typeId == null || _typeId!.isEmpty) {
      setState(() => _error = 'Pick a subcategory from search.');
      return false;
    }
    final typeRow = _rowByTypeId(types, _typeId!);
    if (typeRow == null) {
      setState(() => _error = 'Pick a subcategory from search.');
      return false;
    }
    final typeName = typeRow['name']?.toString().trim() ?? '';
    if (_typeSearchCtrl.text.trim() != typeName) {
      _typeSearchCtrl.text = typeName;
    }
    if (_packagingMode == StockTrackingMode.wholesaleBag) {
      final kg = _parsedKg();
      if (kg == null) {
        setState(() {
          _kgFieldError = 'Kg per bag is required';
          _error = 'Enter kg per bag.';
        });
        return false;
      }
    }
    if (_packagingMode == StockTrackingMode.box) {
      final ipb = double.tryParse(_ipbCtrl.text.trim());
      if (ipb == null || ipb <= 0) {
        setState(() {
          _ipbFieldError = 'Items per box is required';
          _error =
              'Enter items per box (use 1 if each box is one unit).';
        });
        return false;
      }
    }
    if (_packagingMode == StockTrackingMode.tin) {
      final wpt = double.tryParse(_wptCtrl.text.trim());
      if (wpt == null || wpt <= 0) {
        setState(() => _error = 'Enter litres/kg per tin.');
        return false;
      }
    }
    setState(() {
      _error = null;
      _kgFieldError = null;
      _ipbFieldError = null;
    });
    return true;
  }

  void _popPage<T extends Object?>([T? result]) {
    if (!mounted) return;
    popImperativeOrGo(
      context,
      fallbackGo: widget.returnResultOnSave ? '/purchase' : '/catalog',
      result: result,
    );
  }

  Future<void> _exit() async {
    if (_saving) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel save?'),
          content: const Text(
            'Item save is still in progress. Close anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep waiting'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _popPage(false);
  }

  void _invalidateAfterCreate(String itemId) {
    invalidateCatalogCreateSurfaces(
      ref,
      itemId: itemId.isNotEmpty ? itemId : null,
    );
    ref.invalidate(bulkStockListProvider);
  }

  void _resetForAddMore() {
    _nameCtrl.clear();
    _kgCtrl.clear();
    _ipbCtrl.clear();
    _wptCtrl.clear();
    _hsnCtrl.clear();
    _purchaseRateCtrl.clear();
    _sellingRateCtrl.clear();
    _packagingMode = StockTrackingMode.looseKg;
    _bagDetectDismissed = false;
    _bagDetectHint = null;
    _kgFieldError = null;
    _error = null;
  }

  Future<void> _submit({required bool addMore}) async {
    if (!_validate()) return;

    final name = _nameCtrl.text.trim().toUpperCase();
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    final typeRow = _rowByTypeId(types, _typeId!)!;
    final categoryFromType = typeRow['category_id']?.toString() ?? '';

    final supplierIds = <String>[];
    if (_supplierId != null && _supplierId!.isNotEmpty) {
      supplierIds.add(_supplierId!);
    }

    final brokers = ref.read(brokersListProvider).valueOrNull ?? [];
    if (_brokerId != null && _brokerId!.isNotEmpty) {
      Map<String, dynamic>? brow;
      for (final b in brokers) {
        if (b['id']?.toString() == _brokerId) {
          brow = b;
          break;
        }
      }
      if (brow == null) {
        setState(() => _error = 'Pick a broker from search or clear broker.');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final hsn = _hsnCtrl.text.trim();
    final purchaseText = _purchaseRateCtrl.text.trim();
    final sellingText = _sellingRateCtrl.text.trim();
    final purchaseRate =
        purchaseText.isEmpty ? null : double.tryParse(purchaseText);
    final sellingRate =
        sellingText.isEmpty ? null : double.tryParse(sellingText);
    final brokerIds = (_brokerId != null && _brokerId!.isNotEmpty)
        ? <String>[_brokerId!]
        : const <String>[];

    final defaultUnit = StockTrackingMode.catalogUnitForMode(_packagingMode);
    final kgPerBag = _modeUsesWeightField ? _parsedKg() : null;
    final ipb = double.tryParse(_ipbCtrl.text.trim());
    final wpt = double.tryParse(_wptCtrl.text.trim());

    try {
      final created = await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryFromType,
            name: name,
            typeId: typeRow['id']?.toString(),
            defaultUnit: defaultUnit,
            defaultSupplierIds: supplierIds,
            defaultBrokerIds: brokerIds,
            hsnCode: hsn.isEmpty ? null : hsn,
            defaultKgPerBag: kgPerBag,
            defaultItemsPerBox:
                _packagingMode == StockTrackingMode.box && ipb != null && ipb > 0
                    ? ipb
                    : null,
            defaultWeightPerTin:
                _packagingMode == StockTrackingMode.tin && wpt != null && wpt > 0
                    ? wpt
                    : null,
            defaultLandingCost: purchaseRate,
            defaultSellingCost: sellingRate,
            packageType: _packageTypeForMode(_packagingMode),
          ).timeout(const Duration(seconds: 45));

      if (!mounted) return;
      final newId = created['id']?.toString() ?? '';
      final itemCode = created['item_code']?.toString() ?? '';
      final existingBarcode = created['barcode']?.toString() ?? '';
      if (newId.isNotEmpty &&
          itemCode.isNotEmpty &&
          existingBarcode.isEmpty) {
        try {
          await ref.read(hexaApiProvider).patchCatalogItemBarcode(
                businessId: session.primaryBusiness.id,
                itemId: newId,
                barcode: itemCode,
              );
        } catch (_) {
          // Non-fatal — item created; barcode can be assigned later.
        }
      }
      await CatalogCreatePrefs.save(
        businessId: session.primaryBusiness.id,
        supplierId: _supplierId,
        brokerId: _brokerId,
      );
      _invalidateAfterCreate(newId);
      if (addMore) {
        setState(() {
          _saving = false;
          _resetForAddMore();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              itemCode.isEmpty
                  ? 'Saved "$name". Add another.'
                  : 'Saved "$name" · $itemCode. Add another.',
            ),
            action: newId.isNotEmpty
                ? SnackBarAction(
                    label: 'Print label',
                    onPressed: () => context.push(
                      '/barcode/print/${Uri.encodeComponent(newId)}',
                    ),
                  )
                : null,
          ),
        );
        return;
      }

      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _saving = false);
      if (widget.returnResultOnSave && newId.isNotEmpty) {
        _popPage(<String, dynamic>{'id': newId, 'name': name});
        return;
      }
      if (newId.isNotEmpty) {
        _popPage();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                itemCode.isEmpty
                    ? 'Item "$name" created'
                    : 'Item "$name" · $itemCode',
              ),
              action: SnackBarAction(
                label: 'Print label',
                onPressed: () => context.push(
                  '/barcode/print/${Uri.encodeComponent(newId)}',
                ),
              ),
            ),
          );
          context.push('/catalog/item/$newId');
        }
        return;
      }
      _popPage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Item "$name" created')),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save timed out. Check connection and try again.';
      });
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to save item. ${userFacingError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(categoryTypesIndexProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);
    final brokersAsync = ref.watch(brokersListProvider);

    ref.listen(categoryTypesIndexProvider, (prev, next) {
      next.whenData((types) {
        if (!mounted || _prefilled) return;
        final sups = ref.read(suppliersListProvider).valueOrNull ?? [];
        final brokers = ref.read(brokersListProvider).valueOrNull ?? [];
        _maybePrefill(types, sups, brokers);
      });
    });
    ref.listen(suppliersListProvider, (prev, next) {
      next.whenData((sups) {
        if (!mounted || _prefilled) return;
        final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
        if (types.isEmpty) return;
        final brokers = ref.read(brokersListProvider).valueOrNull ?? [];
        _maybePrefill(types, sups, brokers);
        unawaited(_loadSavedParty());
      });
    });
    ref.listen(brokersListProvider, (prev, next) {
      next.whenData((_) {
        if (!mounted) return;
        unawaited(_loadSavedParty());
      });
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _exit();
      },
      child: SizedBox.expand(
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: const Text('New item'),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => unawaited(_exit()),
            ),
          ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    ..._buildPartyFields(suppliersAsync, brokersAsync),
                    typesAsync.whenForm(
                      initialLoading: () => const LinearProgressIndicator(),
                      reloadingBanner: (_) => formReloadBanner(),
                      data: (types) {
                        if (types.isEmpty) {
                          return const Text(
                            'No subcategories — add in Catalog first.',
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Subcategory *'),
                            const SizedBox(height: 6),
                            InlineSearchField(
                              items: _typeItems(types),
                              controller: _typeSearchCtrl,
                              placeholder: 'Search subcategory…',
                              onSelected: (it) {
                                _selectingType = true;
                                setState(() {
                                  _typeId = it.id;
                                  _typeSearchCtrl.text = it.label;
                                });
                                _selectingType = false;
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Item name *',
                        hintText: 'e.g. ULUVA 30 KG',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    if (_bagDetectHint != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _bagDetectHint!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _dismissBagDetection,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    PackagingTypeSelector(
                      compactLayout: true,
                      selectedMode: _packagingMode,
                      onModeChanged: _onPackagingModeChanged,
                      suggestedMode: StockTrackingMode.suggestFromName(
                        _nameCtrl.text,
                      ),
                      weightController: _kgCtrl,
                      itemsPerBoxController: _ipbCtrl,
                      weightPerTinController: _wptCtrl,
                      weightError: _kgFieldError,
                      boxError: _ipbFieldError,
                      itemNameForAutofill: _nameCtrl.text,
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'More options',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      subtitle: const Text('HSN and rates (item code auto-generated)'),
                      children: _buildMoreOptions(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  List<Widget> _buildPartyFields(
    AsyncValue<List<Map<String, dynamic>>> suppliersAsync,
    AsyncValue<List<Map<String, dynamic>>> brokersAsync,
  ) {
    return [
      suppliersAsync.whenForm(
        initialLoading: () => const SizedBox.shrink(),
        reloadingBanner: (_) => formReloadBanner(),
        data: (sups) {
          if (sups.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Supplier (optional)')),
                  if (_supplierId != null && _supplierId!.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _supplierId = null;
                        _supplierSearchCtrl.clear();
                      }),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              InlineSearchField(
                items: _supplierItems(sups),
                controller: _supplierSearchCtrl,
                placeholder: 'Search supplier…',
                onSelected: (it) => setState(() => _supplierId = it.id),
              ),
              const SizedBox(height: 14),
            ],
          );
        },
      ),
      brokersAsync.whenForm(
        initialLoading: () => const SizedBox.shrink(),
        data: (rows) {
          if (rows.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Broker (optional)')),
                  if (_brokerId != null && _brokerId!.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _brokerId = null;
                        _brokerSearchCtrl.clear();
                      }),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              InlineSearchField(
                items: _brokerItems(rows),
                controller: _brokerSearchCtrl,
                placeholder: 'Search broker…',
                onSelected: (it) => setState(() => _brokerId = it.id),
              ),
              const SizedBox(height: 14),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _buildMoreOptions() {
    return [
      TextField(
        controller: _hsnCtrl,
        decoration: const InputDecoration(
          labelText: 'HSN (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _purchaseRateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Purchase rate (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _sellingRateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Selling rate (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => _submit(addMore: true),
            child: const Text('Save & add more'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : () => _submit(addMore: false),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create item'),
          ),
        ],
      ),
    );
  }
}
