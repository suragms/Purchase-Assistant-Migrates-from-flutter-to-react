import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../shared/widgets/inline_search_field.dart';

/// Full-screen quick catalog item create from Home (subcategory-first, optional broker, save loop).
class QuickAddCatalogItemPage extends ConsumerStatefulWidget {
  const QuickAddCatalogItemPage({super.key});

  @override
  ConsumerState<QuickAddCatalogItemPage> createState() =>
      _QuickAddCatalogItemPageState();
}

class _QuickAddCatalogItemPageState
    extends ConsumerState<QuickAddCatalogItemPage> {
  final _nameCtrl = TextEditingController();
  final _itemCodeCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _purchaseRateCtrl = TextEditingController();
  final _sellingRateCtrl = TextEditingController();
  final _typeSearchCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _brokerSearchCtrl = TextEditingController();

  String? _typeId;
  String? _supplierId;
  String? _brokerId;
  String _unit = 'kg';
  bool _saving = false;
  String? _error;

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

  Future<void> _submit({required bool addMore}) async {
    final name = _nameCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Item name is required.');
      return;
    }
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    final typeRow =
        _typeId != null ? _rowByTypeId(types, _typeId!) : null;
    final typeNameField = _typeSearchCtrl.text.trim();
    if (typeRow == null ||
        typeRow['name']?.toString().trim() != typeNameField) {
      setState(() => _error = 'Pick a subcategory from the search results.');
      return;
    }
    final categoryFromType = typeRow['category_id']?.toString();
    if (categoryFromType == null || categoryFromType.isEmpty) {
      setState(() => _error = 'Invalid subcategory row — try again.');
      return;
    }

    final sups = ref.read(suppliersListProvider).valueOrNull ?? [];
    if (sups.isEmpty) {
      setState(() => _error =
          'Add at least one supplier in Contacts before creating an item.');
      return;
    }
    String supplierId;
    if (sups.length == 1) {
      supplierId = sups.first['id']?.toString() ?? '';
    } else {
      supplierId = _supplierId ?? '';
      if (supplierId.isEmpty) {
        setState(() => _error = 'Select a default supplier.');
        return;
      }
      Map<String, dynamic>? srow;
      for (final s in sups) {
        if (s['id']?.toString() == supplierId) {
          srow = s;
          break;
        }
      }
      final supField = _supplierSearchCtrl.text.trim();
      if (srow == null ||
          srow['name']?.toString().trim() != supField) {
        setState(() => _error = 'Pick a supplier from the search results.');
        return;
      }
    }
    if (supplierId.isEmpty) {
      setState(() => _error = 'Select a default supplier.');
      return;
    }
    if (_unit == 'bag') {
      final kg = double.tryParse(_kgCtrl.text.trim());
      if (kg == null || kg <= 0) {
        setState(() => _error = 'Please enter weight per bag (kg).');
        return;
      }
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
      final broField = _brokerSearchCtrl.text.trim();
      if (brow == null ||
          brow['name']?.toString().trim() != broField) {
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
      await ref.read(hexaApiProvider).createCatalogItem(
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
          );
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(categoryTypesIndexProvider);
      ref.invalidate(homeDashboardDataProvider);
      ref.invalidate(stockListProvider);
      ref.invalidate(bulkStockListProvider);
      if (!mounted) return;
      if (addMore) {
        setState(() {
          _saving = false;
          _nameCtrl.clear();
          _itemCodeCtrl.clear();
          _kgCtrl.clear();
          _hsnCtrl.clear();
          _purchaseRateCtrl.clear();
          _sellingRateCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name". Add another item.')),
        );
      } else {
        setState(() => _saving = false);
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        messenger.showSnackBar(
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Item'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Pick subcategory first — category is set automatically. Then supplier and optional broker.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            typesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, st) {
                logSilencedApiError(e, st);
                return InlineLoadError(
                  title: 'Could not load subcategories',
                  error: e,
                  onRetry: () => ref.invalidate(categoryTypesIndexProvider),
                );
              },
              data: (types) {
                if (types.isEmpty) {
                  return const Text(
                    'No subcategories yet — add categories/types in Catalog.',
                  );
                }
                final items = _typeItems(types);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Subcategory (type) *',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    InlineSearchField(
                      key: ValueKey<String>('qa_types_${types.length}'),
                      items: items,
                      controller: _typeSearchCtrl,
                      placeholder: 'Type to search subcategory…',
                      onSelected: (it) {
                        setState(() => _typeId = it.id);
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            suppliersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, st) {
                logSilencedApiError(e, st);
                return InlineLoadError(
                  title: 'Could not load suppliers',
                  error: e,
                  onRetry: () => ref.invalidate(suppliersListProvider),
                );
              },
              data: (sups) {
                if (sups.isEmpty) {
                  return const Text(
                    'Add at least one supplier in Contacts before creating items.',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  );
                }
                if (sups.length == 1) {
                  final n = sups.first['name']?.toString() ?? 'Supplier';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Default supplier: $n',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  );
                }
                final items = _supplierItems(sups);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Default supplier *',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    InlineSearchField(
                      key: ValueKey<String>('qa_sup_${sups.length}_$_supplierId'),
                      items: items,
                      controller: _supplierSearchCtrl,
                      placeholder: 'Type to search supplier…',
                      onSelected: (it) =>
                          setState(() => _supplierId = it.id),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            brokersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const Text('Could not load brokers.'),
              data: (rows) {
                if (rows.isEmpty) {
                  return Text(
                    'No brokers yet — optional. Add one from Home → broker icon.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  );
                }
                final items = _brokerItems(rows);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Default broker (optional)',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
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
                      key: ValueKey<String>('qa_bro_${rows.length}_$_brokerId'),
                      items: items,
                      controller: _brokerSearchCtrl,
                      placeholder: 'Type to search broker…',
                      onSelected: (it) =>
                          setState(() => _brokerId = it.id),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Item name *',
                hintText: 'e.g. THUVARA JP 50 KG',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'Item code (optional)',
                helperText: 'Leave empty to auto-generate later. Staff should verify before printing labels.',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hsnCtrl,
              decoration: const InputDecoration(
                labelText: 'HSN code (optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Unit: '),
                const SizedBox(width: 8),
                for (final u in ['kg', 'bag', 'piece'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(u),
                      selected: _unit == u,
                      onSelected: (_) => setState(() {
                        _unit = u;
                        _kgCtrl.clear();
                      }),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Box or tin units: use Catalog → Add item.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (_unit == 'bag') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _kgCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Weight per bag (kg)',
                  hintText: 'e.g. 50',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
            const SizedBox(height: 8),
            const Text(
              'Barcode option: add item code now, or generate barcode from item detail after saving.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _submit(addMore: true),
                    child: const Text('Save & add more'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _submit(addMore: false),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
