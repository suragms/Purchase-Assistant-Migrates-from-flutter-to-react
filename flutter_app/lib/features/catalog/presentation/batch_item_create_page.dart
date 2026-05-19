import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';

class _BatchLine {
  _BatchLine()
      : name = TextEditingController(),
        kgPerBag = TextEditingController(),
        itemsPerBox = TextEditingController(),
        weightPerTin = TextEditingController();

  final TextEditingController name;
  String? categoryId;
  String? typeId;
  String unit = 'kg';
  final TextEditingController kgPerBag;
  final TextEditingController itemsPerBox;
  final TextEditingController weightPerTin;

  void dispose() {
    name.dispose();
    kgPerBag.dispose();
    itemsPerBox.dispose();
    weightPerTin.dispose();
  }
}

/// Batch-create catalog items with this supplier as default.
class BatchItemCreatePage extends ConsumerStatefulWidget {
  const BatchItemCreatePage({super.key, required this.supplierId});

  final String supplierId;

  @override
  ConsumerState<BatchItemCreatePage> createState() =>
      _BatchItemCreatePageState();
}

class _BatchItemCreatePageState extends ConsumerState<BatchItemCreatePage> {
  final _lines = <_BatchLine>[_BatchLine()];
  bool _saving = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() => _lines.add(_BatchLine()));
  }

  void _removeAt(int i) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines[i].dispose();
      _lines.removeAt(i);
    });
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final sid = widget.supplierId;
    final payload = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final name = l.name.text.trim().toUpperCase();
      if (name.isEmpty) continue;
      if (l.typeId == null || l.typeId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Each row needs a subcategory (type).')),
          );
        }
        return;
      }
      final u = l.unit;
      final kg = double.tryParse(l.kgPerBag.text.trim());
      final ipb = double.tryParse(l.itemsPerBox.text.trim());
      final wpt = double.tryParse(l.weightPerTin.text.trim());
      if (u == 'bag' && (kg == null || kg <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Enter kg per bag for "$name".')),
          );
        }
        return;
      }
      if (u == 'box' && (ipb == null || ipb <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Enter items per box for "$name".')),
          );
        }
        return;
      }
      if (u == 'tin' && (wpt == null || wpt <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Enter weight per tin for "$name".')),
          );
        }
        return;
      }
      payload.add({
        'name': name,
        'type_id': l.typeId,
        'default_unit': u,
        if (u == 'bag') 'default_kg_per_bag': kg,
        if (u == 'box') 'default_items_per_box': ipb,
        if (u == 'tin') 'default_weight_per_tin': wpt,
        'default_supplier_ids': [sid],
      });
    }
    if (payload.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one item name.')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final out = await ref.read(hexaApiProvider).createCatalogItemsBatch(
            businessId: bid,
            items: payload,
          );
      final created = out['created'];
      final skipped = out['skipped'];
      ref.invalidate(catalogItemsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Created ${created ?? payload.length} item(s)'
              '${skipped != null ? ' · skipped $skipped' : ''}.',
            ),
          ),
        );
        context.pop();
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
    final dropdownMenuMax =
        math.min(260.0, MediaQuery.sizeOf(context).height * 0.38);
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch add items'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/supplier/${widget.supplierId}'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            'New items are linked to this supplier. Duplicates in the same '
            'subcategory are skipped on the server.',
            style: tt.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_lines.length, (i) {
            final line = _lines[i];
            final typesAsync = line.categoryId == null
                ? const AsyncValue<List<Map<String, dynamic>>>.data([])
                : ref.watch(categoryTypesListProvider(line.categoryId!));
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Item ${i + 1}',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (_lines.length > 1)
                          IconButton(
                            tooltip: 'Remove',
                            icon: Icon(Icons.delete_outline,
                                color: Colors.red.shade700),
                            onPressed: () => _removeAt(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    catsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, st) {
                        logSilencedApiError(e, st);
                        return InlineLoadError(
                          title: 'Could not load categories',
                          error: e,
                          onRetry: () =>
                              ref.invalidate(itemCategoriesListProvider),
                        );
                      },
                      data: (cats) {
                        if (cats.isEmpty) {
                          return const Text('No categories — create in Catalog.');
                        }
                        return DropdownButtonFormField<String>(
                          key: ValueKey('cat_${i}_${line.categoryId}'),
                          menuMaxHeight: dropdownMenuMax,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: line.categoryId,
                          hint: const Text('Select'),
                          items: [
                            for (final c in cats)
                              DropdownMenuItem(
                                value: c['id']?.toString(),
                                child: Text(
                                  c['name']?.toString() ?? '—',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            line.categoryId = v;
                            line.typeId = null;
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    typesAsync.when(
                      loading: () => line.categoryId == null
                          ? const SizedBox.shrink()
                          : const LinearProgressIndicator(),
                      error: (e, st) {
                        logSilencedApiError(e, st);
                        return InlineLoadError(
                          title: 'Could not load subcategories',
                          error: e,
                          onRetry: () => ref.invalidate(
                            categoryTypesListProvider(line.categoryId!),
                          ),
                        );
                      },
                      data: (types) {
                        if (line.categoryId == null) {
                          return const SizedBox.shrink();
                        }
                        if (types.isEmpty) {
                          return const Text('No subcategories in this category.');
                        }
                        return DropdownButtonFormField<String>(
                          key: ValueKey('type_${i}_${line.typeId}'),
                          menuMaxHeight: dropdownMenuMax,
                          decoration: const InputDecoration(
                            labelText: 'Subcategory *',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: line.typeId,
                          hint: const Text('Select type'),
                          items: [
                            for (final t in types)
                              DropdownMenuItem(
                                value: t['id']?.toString(),
                                child: Text(
                                  t['name']?.toString() ?? '—',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => line.typeId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: line.name,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Item name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final u in ['kg', 'bag', 'box', 'tin', 'piece'])
                          ChoiceChip(
                            label: Text(u),
                            selected: line.unit == u,
                            onSelected: (_) => setState(() {
                              line.unit = u;
                              line.kgPerBag.clear();
                              line.itemsPerBox.clear();
                              line.weightPerTin.clear();
                            }),
                          ),
                      ],
                    ),
                    if (line.unit == 'bag') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: line.kgPerBag,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Kg per bag *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (line.unit == 'box') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: line.itemsPerBox,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Items per box *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (line.unit == 'tin') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: line.weightPerTin,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Weight per tin *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add another row'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create items'),
          ),
        ],
      ),
    );
  }
}
