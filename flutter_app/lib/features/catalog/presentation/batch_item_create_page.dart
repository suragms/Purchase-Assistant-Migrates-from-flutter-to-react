import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/async_value_form.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/providers/catalog_providers.dart';
import '../catalog_taxonomy_utils.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/unit_engine/stock_tracking_profile.dart';
import '../../../shared/widgets/packaging_type_selector.dart';

class _BatchLine {
  _BatchLine() : name = TextEditingController();

  final TextEditingController name;
  String? categoryId;
  String? typeId;
  String unit = 'kg';
  String packagingMode = StockTrackingMode.looseKg;

  void dispose() {
    name.dispose();
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
      default:
        return 'PIECE';
    }
  }

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
      final kg = u == 'bag' ? StockTrackingMode.parseKgFromName(name) : null;
      if (u == 'bag' && (kg == null || kg <= 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bag items need weight in name (e.g. 50KG): "$name".'),
            ),
          );
        }
        return;
      }
      payload.add({
        'name': name,
        'type_id': l.typeId,
        'default_unit': u,
        'package_type': _packageTypeForMode(l.packagingMode),
        if (u == 'bag') 'default_kg_per_bag': kg,
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
      final itemsOut = out['items'];
      final codes = <String>[];
      String? firstId;
      if (itemsOut is List) {
        for (final raw in itemsOut) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final code = m['item_code']?.toString().trim() ?? '';
          if (code.isNotEmpty) codes.add(code);
          firstId ??= m['id']?.toString();
        }
      }
      ref.invalidate(catalogItemsListProvider);
      if (mounted) {
        final codeHint = codes.isEmpty
            ? ''
            : codes.length <= 3
                ? ' · ${codes.join(', ')}'
                : ' · ${codes.take(3).join(', ')} +${codes.length - 3} more';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Created ${created ?? payload.length} item(s)'
              '${skipped != null ? ' · skipped $skipped' : ''}'
              '$codeHint',
            ),
            action: firstId != null && firstId.isNotEmpty
                ? SnackBarAction(
                    label: 'Print first',
                    onPressed: () => context.push(
                      '/barcode/print/${Uri.encodeComponent(firstId!)}',
                    ),
                  )
                : null,
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
                    catsAsync.whenForm(
                      initialLoading: () => const LinearProgressIndicator(),
                      reloadingBanner: (_) => formReloadBanner(),
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
                    Consumer(
                      builder: (context, ref, _) {
                        final indexAsync = ref.watch(categoryTypesIndexProvider);
                        final typesAsync = line.categoryId == null
                            ? const AsyncValue<List<Map<String, dynamic>>>.data([])
                            : indexAsync.when(
                                data: (index) => AsyncValue.data(
                                  typesForCategory(index, line.categoryId!),
                                ),
                                loading: () => const AsyncValue.loading(),
                                error: (e, st) => AsyncValue.error(e, st),
                              );
                        return typesAsync.whenForm(
                          initialLoading: () => line.categoryId == null
                              ? const SizedBox.shrink()
                              : const LinearProgressIndicator(),
                          error: (e, st) {
                            logSilencedApiError(e, st);
                            return InlineLoadError(
                              title: 'Could not load subcategories',
                              error: e,
                              onRetry: () => ref.invalidate(
                                categoryTypesIndexProvider,
                              ),
                            );
                          },
                          data: (types) {
                            if (line.categoryId == null) {
                              return const SizedBox.shrink();
                            }
                            if (types.isEmpty) {
                              return const Text(
                                'No subcategories in this category.',
                              );
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
                      onChanged: (_) {
                        final suggested =
                            StockTrackingMode.suggestFromName(line.name.text);
                        if (suggested != null) {
                          setState(() {
                            line.packagingMode = suggested;
                            line.unit =
                                StockTrackingMode.catalogUnitForMode(suggested);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    PackagingTypeSelector(
                      selectedMode: line.packagingMode,
                      onModeChanged: (m) => setState(() {
                        line.packagingMode = m;
                        line.unit = StockTrackingMode.catalogUnitForMode(m);
                      }),
                    ),
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
