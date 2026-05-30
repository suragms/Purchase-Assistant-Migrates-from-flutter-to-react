import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/navigation_ext.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/unit_engine/stock_tracking_profile.dart';
import '../../../shared/widgets/inline_search_field.dart';
import '../../../shared/widgets/packaging_type_selector.dart';

/// Fast catalog item create — supplier/broker first, optional item code.
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
  final _itemCodeCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _purchaseRateCtrl = TextEditingController();
  final _sellingRateCtrl = TextEditingController();
  final _typeSearchCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _brokerSearchCtrl = TextEditingController();

  int _step = 0;
  String? _typeId;
  String? _supplierId;
  String? _brokerId;
  String _unit = 'kg';
  String _packagingMode = StockTrackingMode.retailPacket;
  bool _saving = false;
  String? _error;
  bool _prefilled = false;

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

  String _modeForUnit(String unit) {
    switch (unit) {
      case 'bag':
        return StockTrackingMode.wholesaleBag;
      case 'kg':
        return StockTrackingMode.looseKg;
      case 'box':
        return StockTrackingMode.box;
      case 'tin':
        return StockTrackingMode.tin;
      case 'piece':
      default:
        return StockTrackingMode.retailPacket;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _itemCodeCtrl.dispose();
    _kgCtrl.dispose();
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
    if (widget.defaultSupplierId != null && widget.defaultSupplierId!.isNotEmpty) {
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
    final presetType = widget.presetTypeId;
    if (presetType != null && presetType.isNotEmpty) {
      final row = _rowByTypeId(types, presetType);
      if (row != null) {
        _typeId = presetType;
        _typeSearchCtrl.text = row['name']?.toString() ?? '';
      }
    }
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

  bool _validateStep0() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Item name is required.');
      return false;
    }
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    final typeRow =
        _typeId != null ? _rowByTypeId(types, _typeId!) : null;
    if (typeRow == null ||
        typeRow['name']?.toString().trim() != _typeSearchCtrl.text.trim()) {
      setState(() => _error = 'Pick a subcategory from search.');
      return false;
    }
    final sups = ref.read(suppliersListProvider).valueOrNull ?? [];
    if (sups.isEmpty) {
      setState(() => _error = 'Add a supplier in Contacts first.');
      return false;
    }
    if (sups.length > 1) {
      if (_supplierId == null || _supplierId!.isEmpty) {
        setState(() => _error = 'Select a supplier.');
        return false;
      }
    }
    if (_unit == 'bag') {
      final kg = double.tryParse(_kgCtrl.text.trim());
      if (kg == null || kg <= 0) {
        setState(() => _error = 'Enter weight per bag (kg).');
        return false;
      }
    }
    setState(() => _error = null);
    return true;
  }

  void _goNext() {
    if (!_validateStep0()) return;
    setState(() => _step = 1);
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step -= 1);
    }
  }

  void _popPage<T extends Object?>([T? result]) {
    if (!mounted) return;
    popImperativeOrGo(
      context,
      fallbackGo: widget.returnResultOnSave ? '/purchase/new' : '/catalog',
      result: result,
    );
  }

  Future<void> _exit() async {
    _popPage(false);
  }

  Future<void> _submit({required bool addMore}) async {
    if (!_validateStep0()) {
      setState(() => _step = 0);
      return;
    }
    final name = _nameCtrl.text.trim().toUpperCase();
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    final typeRow = _rowByTypeId(types, _typeId!)!;
    final categoryFromType = typeRow['category_id']?.toString() ?? '';

    final sups = ref.read(suppliersListProvider).valueOrNull ?? [];
    final supplierId = sups.length == 1
        ? sups.first['id']?.toString() ?? ''
        : _supplierId ?? '';

    final brokers = ref.read(brokersListProvider).valueOrNull ?? [];
    if (_brokerId != null && _brokerId!.isNotEmpty) {
      Map<String, dynamic>? brow;
      for (final b in brokers) {
        if (b['id']?.toString() == _brokerId) {
          brow = b;
          break;
        }
      }
      if (brow == null ||
          brow['name']?.toString().trim() != _brokerSearchCtrl.text.trim()) {
        setState(() => _error = 'Pick a broker from search or clear broker.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _saving = false);
      return;
    }
    final hsn = _hsnCtrl.text.trim();
    final itemCode = _itemCodeCtrl.text.trim().toUpperCase();
    final purchaseRate = double.tryParse(_purchaseRateCtrl.text.trim());
    final sellingRate = double.tryParse(_sellingRateCtrl.text.trim());
    final brokerIds = (_brokerId != null && _brokerId!.isNotEmpty)
        ? <String>[_brokerId!]
        : const <String>[];
    try {
      final created = await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryFromType,
            name: name,
            typeId: typeRow['id']?.toString(),
            defaultUnit: _unit,
            defaultSupplierIds: [supplierId],
            defaultBrokerIds: brokerIds,
            hsnCode: hsn.isEmpty ? null : hsn,
            itemCode: itemCode.isEmpty ? null : itemCode,
            defaultKgPerBag: _unit == 'bag'
                ? double.tryParse(_kgCtrl.text.trim())
                : null,
            defaultLandingCost: purchaseRate,
            defaultSellingCost: sellingRate,
            packageType: _packageTypeForMode(_packagingMode),
          );
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(categoryTypesIndexProvider);
      ref.invalidate(homeDashboardDataProvider);
      ref.invalidate(stockListProvider);
      ref.invalidate(bulkStockListProvider);
      if (!mounted) return;
      final newId = created['id']?.toString() ?? '';
      if (addMore) {
        setState(() {
          _saving = false;
          _step = 0;
          _nameCtrl.clear();
          _itemCodeCtrl.clear();
          _kgCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name". Add another.')),
        );
      } else if (widget.returnResultOnSave && newId.isNotEmpty) {
        _popPage(<String, dynamic>{'id': newId, 'name': name});
      } else if (newId.isNotEmpty) {
        _popPage(<String, dynamic>{'id': newId, 'name': name});
      } else {
        _popPage();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Item "$name" created')),
        );
      }
    } catch (e, st) {
      logSilencedApiError(e, st);
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

    typesAsync.whenData((types) {
      final sups = suppliersAsync.valueOrNull ?? [];
      final brokers = brokersAsync.valueOrNull ?? [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePrefill(types, sups, brokers);
      });
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_step > 0) {
          _goBack();
          return;
        }
        await _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New item'),
              Text(
                'Step ${_step + 1} of 2',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          leading: IconButton(
            icon: Icon(_step > 0 ? Icons.arrow_back_rounded : Icons.close_rounded),
            onPressed: _saving
                ? null
                : () {
                    if (_step > 0) {
                      _goBack();
                    } else {
                      unawaited(_exit());
                    }
                  },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: _step == 0
                      ? _buildStep0(suppliersAsync, brokersAsync, typesAsync)
                      : _buildStep1(),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep0(
    AsyncValue<List<Map<String, dynamic>>> suppliersAsync,
    AsyncValue<List<Map<String, dynamic>>> brokersAsync,
    AsyncValue<List<Map<String, dynamic>>> typesAsync,
  ) {
    return [
      Text(
        'Supplier and item details',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
      const SizedBox(height: 12),
      suppliersAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => const Text('Could not load suppliers.'),
        data: (sups) {
          if (sups.isEmpty) {
            return const Text(
              'Add at least one supplier in Contacts before creating items.',
              style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
            );
          }
          if (sups.length == 1) {
            final n = sups.first['name']?.toString() ?? 'Supplier';
            if (_supplierId == null) {
              _supplierId = sups.first['id']?.toString();
              _supplierSearchCtrl.text = n;
            }
            return Text('Supplier: $n', style: const TextStyle(fontWeight: FontWeight.w700));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Supplier *'),
              const SizedBox(height: 6),
              InlineSearchField(
                key: ValueKey('ci_sup_${sups.length}_$_supplierId'),
                items: _supplierItems(sups),
                controller: _supplierSearchCtrl,
                placeholder: 'Search supplier…',
                onSelected: (it) => setState(() => _supplierId = it.id),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 14),
      brokersAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (rows) {
          if (rows.isEmpty) {
            return Text(
              'Broker optional — add from Contacts if needed.',
              style: Theme.of(context).textTheme.bodySmall,
            );
          }
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
                key: ValueKey('ci_bro_${rows.length}_$_brokerId'),
                items: _brokerItems(rows),
                controller: _brokerSearchCtrl,
                placeholder: 'Search broker…',
                onSelected: (it) => setState(() => _brokerId = it.id),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 14),
      typesAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => const Text('Could not load subcategories.'),
        data: (types) {
          if (types.isEmpty) {
            return const Text('No subcategories — add in Catalog first.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Subcategory *'),
              const SizedBox(height: 6),
              InlineSearchField(
                key: ValueKey('ci_type_${types.length}_$_typeId'),
                items: _typeItems(types),
                controller: _typeSearchCtrl,
                placeholder: 'Search subcategory…',
                onSelected: (it) => setState(() => _typeId = it.id),
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
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.characters,
      ),
      const SizedBox(height: 14),
      PackagingTypeSelector(
        selectedMode: _packagingMode,
        onModeChanged: (m) => setState(() {
          _packagingMode = m;
          _unit = StockTrackingMode.catalogUnitForMode(m);
          _kgCtrl.clear();
        }),
        weightController: _kgCtrl,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          for (final u in ['kg', 'bag', 'piece', 'box', 'tin'])
            ChoiceChip(
              label: Text(u.toUpperCase()),
              selected: _unit == u,
              onSelected: (_) => setState(() {
                _unit = u;
                _packagingMode = _modeForUnit(u);
                _kgCtrl.clear();
              }),
            ),
        ],
      ),
      if (_unit == 'bag') ...[
        const SizedBox(height: 8),
        TextField(
          controller: _kgCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Weight per bag (kg) *',
            border: OutlineInputBorder(),
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.red)),
      ],
    ];
  }

  List<Widget> _buildStep1() {
    return [
      Text(
        'Optional codes and rates',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _itemCodeCtrl,
        decoration: const InputDecoration(
          labelText: 'Item code (optional)',
          helperText: 'Staff can add later — auto-generated if blank.',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.characters,
      ),
      const SizedBox(height: 12),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Purchase rate',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _sellingRateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Selling rate',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.red)),
      ],
    ];
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(onPressed: _saving ? null : _goBack, child: const Text('Back'))
          else
            const SizedBox(width: 8),
          const Spacer(),
          if (_step == 0)
            FilledButton(
              onPressed: _goNext,
              child: const Text('Next'),
            )
          else ...[
            OutlinedButton(
              onPressed: _saving ? null : () => _submit(addMore: true),
              child: const Text('Save & add more'),
            ),
            const SizedBox(width: 8),
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
        ],
      ),
    );
  }
}
