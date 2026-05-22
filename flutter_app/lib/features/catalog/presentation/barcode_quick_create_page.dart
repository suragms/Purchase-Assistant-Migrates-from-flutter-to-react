import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/services/duplicate_detection_service.dart';
import '../../../core/utils/item_code_format.dart';
import '../../../shared/widgets/inline_search_field.dart';

/// Minimal item create after unknown barcode scan (no supplier/broker/HSN).
class BarcodeQuickCreatePage extends ConsumerStatefulWidget {
  const BarcodeQuickCreatePage({super.key, required this.barcode});

  final String barcode;

  @override
  ConsumerState<BarcodeQuickCreatePage> createState() =>
      _BarcodeQuickCreatePageState();
}

class _BarcodeQuickCreatePageState extends ConsumerState<BarcodeQuickCreatePage> {
  final _itemCodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _typeSearchCtrl = TextEditingController();
  final _kgCtrl = TextEditingController();
  late final CatalogDuplicateDebouncer _debouncer;

  String? _typeId;
  String _unit = 'kg';
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _dupHits = const [];

  @override
  void initState() {
    super.initState();
    _debouncer = CatalogDuplicateDebouncer(ref.read(hexaApiProvider));
  }

  @override
  void dispose() {
    _itemCodeCtrl.dispose();
    _nameCtrl.dispose();
    _typeSearchCtrl.dispose();
    _kgCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
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

  void _onNameChanged(String v) {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    _debouncer.schedule(
      businessId: session.primaryBusiness.id,
      name: v,
      typeId: _typeId,
      onResult: (hits) {
        if (mounted) setState(() => _dupHits = hits);
      },
    );
  }

  Future<void> _save() async {
    final code = normalizeItemCode(_itemCodeCtrl.text);
    final name = _nameCtrl.text.trim().toUpperCase();
    if (!isValidItemCode(code)) {
      setState(() => _error = 'Enter a valid item code (A-Z, 0-9, -, _)');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Item name is required');
      return;
    }
    final types = ref.read(categoryTypesIndexProvider).valueOrNull ?? [];
    Map<String, dynamic>? typeRow;
    for (final m in types) {
      if (m['id']?.toString() == _typeId) {
        typeRow = m;
        break;
      }
    }
    if (typeRow == null ||
        typeRow['name']?.toString().trim() != _typeSearchCtrl.text.trim()) {
      setState(() => _error = 'Pick a subcategory from search results');
      return;
    }
    if (_unit == 'bag') {
      final kg = double.tryParse(_kgCtrl.text.trim());
      if (kg == null || kg <= 0) {
        setState(() => _error = 'Enter kg per bag');
        return;
      }
    }
    final highDup = _dupHits.any((h) => fuzzyHitScore(h) >= 0.85);
    if (highDup) {
      setState(() => _error = 'Similar item name exists — check duplicates');
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(hexaApiProvider).createCatalogItemFromScan(
            businessId: session.primaryBusiness.id,
            barcode: widget.barcode,
            itemCode: code,
            name: name,
            typeId: _typeId!,
            defaultUnit: _unit,
            defaultKgPerBag: _unit == 'bag'
                ? double.tryParse(_kgCtrl.text.trim())
                : null,
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(catalogItemsListProvider);
      if (!mounted) return;
      final id = created['id']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $name'),
          action: id.isNotEmpty
              ? SnackBarAction(
                  label: 'Print label',
                  onPressed: () => context.push(
                    '/barcode/print/${Uri.encodeComponent(id)}',
                  ),
                )
              : null,
        ),
      );
      context.pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(categoryTypesIndexProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Create from barcode')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Barcode', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                widget.barcode,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _itemCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'Item code *',
                hintText: 'RICE-PONNI-50KG',
              ),
              inputFormatters: [ItemCodeInputFormatter()],
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Item name *'),
              textCapitalization: TextCapitalization.characters,
              onChanged: _onNameChanged,
            ),
            if (_dupHits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Similar: ${_dupHits.take(3).map((h) => h['name']).join(', ')}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFBA7517)),
              ),
            ],
            const SizedBox(height: 12),
            typesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Could not load subcategories'),
              data: (types) => InlineSearchField(
                controller: _typeSearchCtrl,
                placeholder: 'Subcategory *',
                items: _typeItems(types),
                onSelected: (it) => setState(() => _typeId = it.id),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Unit type', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final u in ['kg', 'bag', 'box', 'tin', 'piece'])
                  ChoiceChip(
                    label: Text(u),
                    selected: _unit == u,
                    onSelected: (_) => setState(() => _unit = u),
                  ),
              ],
            ),
            if (_unit == 'bag') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _kgCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kg per bag *'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFA32D2D))),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save item'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Supplier and advanced settings can be added later.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
