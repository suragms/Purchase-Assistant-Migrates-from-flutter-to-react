import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/widgets/business_write_surface_listener.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/search/search_highlight.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/search_picker_sheet.dart';
import '../../../shared/widgets/trade_intel_cards.dart';

/// Items under a subcategory (category type).
class CatalogTypeItemsPage extends ConsumerStatefulWidget {
  const CatalogTypeItemsPage({
    super.key,
    required this.categoryId,
    required this.typeId,
  });

  final String categoryId;
  final String typeId;

  @override
  ConsumerState<CatalogTypeItemsPage> createState() => _CatalogTypeItemsPageState();
}

class _CatalogTypeItemsPageState extends ConsumerState<CatalogTypeItemsPage> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  final Set<String> _selected = {};
  bool _selectionMode = false;
  /// Item IDs hidden immediately while delete API runs (restored on failure).
  final Set<String> _pendingDeleteItemIds = {};
  bool _bulkDeleting = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
  }

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  Future<void> _refresh() async {
    ref.invalidate(categoryTypesListProvider(widget.categoryId));
    ref.invalidate(catalogItemsListProvider);
    ref.invalidate(categoryTradeSummaryProvider(widget.categoryId));
    await ref.read(catalogItemsListProvider.future);
  }

  void _bustWarehouseCachesForDeletedItems(Iterable<String> itemIds) {
    final ids = itemIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    clearStockListRowPatchesForIds(ref, ids);
    for (final id in ids) {
      invalidateWarehouseSurfacesLight(ref, itemId: id);
    }
  }

  Future<void> _deleteItemById(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete “$name”?'),
        actions: [
          TextButton(onPressed: () => d.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => d.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _pendingDeleteItemIds.add(id));
    try {
      await ref.read(hexaApiProvider).deleteCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
          );
      _bustWarehouseCachesForDeletedItems([id]);
      ref.invalidate(catalogItemsListProvider);
      try {
        await ref.read(catalogItemsListProvider.future);
      } catch (_) {}
      invalidateBusinessAggregates(ref);
      if (mounted) {
        setState(() => _pendingDeleteItemIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _pendingDeleteItemIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty || _bulkDeleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selected.length} item(s)?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _bulkDeleting = true);
    final ids = _selected.toList();
    setState(() {
      for (final id in ids) {
        _pendingDeleteItemIds.add(id);
      }
      _selected.clear();
      _selectionMode = false;
    });
    var stoppedEarly = false;
    for (final id in ids) {
      try {
        await ref.read(hexaApiProvider).deleteCatalogItem(
              businessId: session.primaryBusiness.id,
              itemId: id,
            );
      } on DioException catch (e) {
        if (mounted) {
          setState(() => _pendingDeleteItemIds.remove(id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyApiError(e))),
          );
        }
        stoppedEarly = true;
        break;
      }
    }
    _bustWarehouseCachesForDeletedItems(ids);
    ref.invalidate(catalogItemsListProvider);
    try {
      await ref.read(catalogItemsListProvider.future);
    } catch (_) {}
    invalidateBusinessAggregates(ref);
    if (mounted) {
      setState(() {
        _pendingDeleteItemIds.removeAll(ids);
        _bulkDeleting = false;
      });
      if (!stoppedEarly) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    }
  }

  Future<void> _pickMoveTarget() async {
    if (_selected.isEmpty) return;
    final cats = await ref.read(itemCategoriesListProvider.future);
    if (!mounted) return;
    String? targetCat;
    String? targetType;
    await showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
      child: StatefulBuilder(
            builder: (ctx, setSt) {
              return Consumer(
                builder: (context, ref, _) {
                  String catLabel() {
                    if (targetCat == null) return 'Choose category';
                    for (final c in cats) {
                      if (c['id']?.toString() == targetCat) {
                        return c['name']?.toString() ?? '—';
                      }
                    }
                    return 'Choose category';
                  }

                  String typeLabel(List<Map<String, dynamic>> types) {
                    if (targetType == null) return 'Choose subcategory';
                    for (final t in types) {
                      if (t['id']?.toString() == targetType) {
                        return t['name']?.toString() ?? '—';
                      }
                    }
                    return 'Choose subcategory';
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Move ${_selected.length} item(s)',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Text('Category', style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          OutlinedButton(
                            onPressed: () async {
                              final rows = <SearchPickerRow<String>>[
                                for (final c in cats)
                                  if ((c['id']?.toString() ?? '').isNotEmpty)
                                    SearchPickerRow<String>(
                                      value: c['id']!.toString(),
                                      title: c['name']?.toString() ?? '—',
                                    ),
                              ];
                              final id = await showSearchPickerSheet<String>(
                                context: ctx,
                                title: 'Search category',
                                rows: rows,
                                selectedValue: targetCat,
                              );
                              if (!ctx.mounted) return;
                              if (id != null) {
                                setSt(() {
                                  targetCat = id;
                                  targetType = null;
                                });
                              }
                            },
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(catLabel(), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text('Subcategory',
                              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Consumer(
                            builder: (context, ref, _) {
                              if (targetCat == null) {
                                return const OutlinedButton(
                                  onPressed: null,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('Select a category first'),
                                  ),
                                );
                              }
                              final typesAsync = ref.watch(categoryTypesListProvider(targetCat!));
                              return typesAsync.when(
                                skipLoadingOnReload: true,
                                loading: () => const OutlinedButton(
                                  onPressed: null,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('Loading subcategories…'),
                                  ),
                                ),
                                error: (_, __) => const OutlinedButton(
                                  onPressed: null,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('Could not load subcategories'),
                                  ),
                                ),
                                data: (typesRaw) {
                                  final types = typesRaw
                                      .map((e) => Map<String, dynamic>.from(e as Map))
                                      .toList();
                                  return OutlinedButton(
                                    onPressed: () async {
                                      final rows = <SearchPickerRow<String>>[
                                        for (final t in types)
                                          if ((t['id']?.toString() ?? '').isNotEmpty)
                                            SearchPickerRow<String>(
                                              value: t['id']!.toString(),
                                              title: t['name']?.toString() ?? '—',
                                            ),
                                      ];
                                      final id = await showSearchPickerSheet<String>(
                                        context: ctx,
                                        title: 'Search subcategory',
                                        rows: rows,
                                        selectedValue: targetType,
                                      );
                                      if (!ctx.mounted) return;
                                      if (id != null) setSt(() => targetType = id);
                                    },
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        typeLabel(types),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: targetCat == null || targetType == null
                                ? null
                                : () async {
                                    ctx.pop();
                                    final session = ref.read(sessionProvider);
                                    if (session == null) return;
                                    for (final id in _selected.toList()) {
                                      try {
                                        await ref.read(hexaApiProvider).updateCatalogItem(
                                              businessId: session.primaryBusiness.id,
                                              itemId: id,
                                              categoryId: targetCat,
                                              typeId: targetType,
                                              patchTypeId: true,
                                            );
                                      } on DioException catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(friendlyApiError(e))),
                                          );
                                        }
                                        return;
                                      }
                                    }
                                    ref.invalidate(catalogItemsListProvider);
                                    if (context.mounted) {
                                      setState(() {
                                        _selected.clear();
                                        _selectionMode = false;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Items moved')),
                                      );
                                    }
                                  },
                            child: const Text('Apply move'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
    );
  }

  void _onItemLongPress(Map<String, dynamic> it) {
    final id = it['id']?.toString() ?? '';
    final name = it['name']?.toString() ?? '';
    showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit on detail'),
            subtitle: const Text('Change defaults, see history'),
            onTap: () {
              Navigator.pop(context);
              context.push('/catalog/item/$id');
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
            title: Text('Delete', style: TextStyle(color: Colors.red.shade800)),
            onTap: () async {
              Navigator.pop(context);
              await _deleteItemById(id, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.checklist_rounded),
            title: const Text('Select multiple'),
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _selectionMode = true;
                _selected
                  ..clear()
                  ..add(id);
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(categoryTypesListProvider(widget.categoryId));
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final tradeSumAsync =
        ref.watch(categoryTradeSummaryProvider(widget.categoryId));
    final summaryByItemId = tradeSumAsync.maybeWhen(
      data: (m) {
        final raw = m['items'];
        if (raw is! List) return <String, Map<String, dynamic>>{};
        final out = <String, Map<String, dynamic>>{};
        for (final e in raw) {
          if (e is! Map) continue;
          final mm = Map<String, dynamic>.from(e);
          final id = mm['catalog_item_id']?.toString();
          if (id != null && id.isNotEmpty) out[id] = mm;
        }
        return out;
      },
      orElse: () => <String, Map<String, dynamic>>{},
    );

    final typeName = typesAsync.maybeWhen(
      data: (types) {
        for (final t in types) {
          if (t['id']?.toString() == widget.typeId) {
            return t['name']?.toString() ?? 'Subcategory';
          }
        }
        return 'Subcategory';
      },
      orElse: () => 'Subcategory',
    );

    final itemsInType = (itemsAsync.valueOrNull ?? [])
          .where((it) => it['type_id']?.toString() == widget.typeId)
          .where((it) => !_pendingDeleteItemIds.contains(it['id']?.toString()))
          .toList();

    final filtered = _searchQuery.trim().isEmpty
        ? itemsInType
        : catalogFuzzyRank(
            _searchQuery,
            itemsInType,
            (it) => it['name']?.toString() ?? '',
            minScore: 38,
            limit: 500,
          );

    return BusinessWriteSurfaceListener(
      onRefresh: (ref, _) {
        ref.invalidate(categoryTypesListProvider(widget.categoryId));
        ref.invalidate(catalogItemsListProvider);
        ref.invalidate(categoryTradeSummaryProvider(widget.categoryId));
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _selectionMode = false;
                  _selected.clear();
                }),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.popOrGo(
                  '/catalog/category/${widget.categoryId}',
                ),
              ),
        title: Text(
          _selectionMode ? '${_selected.length} selected' : typeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected.clear();
                      for (final it in filtered) {
                        final id = it['id']?.toString();
                        if (id != null && id.isNotEmpty) {
                          _selected.add(id);
                        }
                      }
                    });
                  },
                  child: const Text('Select all'),
                ),
                TextButton(onPressed: _bulkDelete, child: const Text('Delete')),
                TextButton(onPressed: _pickMoveTarget, child: const Text('Move')),
              ]
            : null,
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context
                  .push<bool>(
                    '/catalog/category/${widget.categoryId}/type/${widget.typeId}/add-item',
                  )
                  .then((_) => ref.invalidate(catalogItemsListProvider)),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search items (fuzzy)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchCtrl,
                  builder: (_, val, __) {
                    if (val.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    );
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  itemsInType.isEmpty ? 'No items yet — tap Add item.' : 'No matches.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              ...filtered.map((it) {
                final id = it['id']?.toString() ?? '';
                final name = it['name']?.toString() ?? '';
                final pu = (it['default_purchase_unit'] ?? it['default_unit'])?.toString() ?? '—';
                final last = _num(it['last_purchase_price']);
                final selected = _selected.contains(id);
                final sumRow = summaryByItemId[id];
                final merged = Map<String, dynamic>.from(it);
                merged['name'] = name;
                if (sumRow != null) {
                  merged['period_line_total'] = sumRow['period_line_total'];
                  merged['period_weight_kg'] = sumRow['period_weight_kg'];
                  merged['period_qty_bags'] = sumRow['period_qty_bags'];
                  merged['last_purchase_price'] = sumRow['last_purchase_price'];
                  merged['last_selling_rate'] = sumRow['last_selling_rate'];
                  merged['last_supplier_name'] = sumRow['last_supplier_name'];
                  merged['last_broker_name'] = sumRow['last_broker_name'];
                  merged['last_trade_human_id'] = sumRow['last_trade_human_id'];
                }
                return RepaintBoundary(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                    onTap: () {
                      if (_selectionMode) {
                        setState(() {
                          if (selected) {
                            _selected.remove(id);
                          } else {
                            _selected.add(id);
                          }
                        });
                      } else {
                        context.push('/catalog/item/$id');
                      }
                    },
                    onLongPress: _selectionMode
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            _onItemLongPress(it);
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        _selectionMode ? 10 : 4,
                        4,
                        4,
                        4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectionMode)
                            Padding(
                              padding: const EdgeInsets.only(right: 6, top: 10),
                              child: Icon(
                                selected ? Icons.check_circle : Icons.circle_outlined,
                                color: selected ? HexaColors.brandPrimary : Colors.grey,
                              ),
                            ),
                          Expanded(
                            child: _selectionMode
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: highlightSearchQuery(
                                            name,
                                            _searchQuery.trim(),
                                            baseStyle: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                            highlightStyle: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: Theme.of(context).colorScheme.primary,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        () {
                                          final bagsLbl =
                                              tradeIntelLastPurchaseBagsLabel(
                                                  merged);
                                          final billId = (merged[
                                                      'last_trade_human_id'] ??
                                                  '')
                                              .toString()
                                              .trim();
                                          final tail = [
                                            if (bagsLbl.isNotEmpty) bagsLbl,
                                            if (billId.isNotEmpty) billId,
                                          ].join(' · ');
                                          final base =
                                              'Unit: ${pu.toUpperCase()} · Last ${_inr(last)}';
                                          return tail.isEmpty
                                              ? base
                                              : '$base · $tail';
                                        }(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  )
                                : TradeIntelCategoryItemTile(
                                    row: merged,
                                    onTap: null,
                                    showChevron: false,
                                  ),
                          ),
                          if (!_selectionMode) ...[
                            PopupMenuButton<String>(
                              tooltip: 'Item actions',
                              onSelected: (v) {
                                if (v == 'edit') {
                                  context.push('/catalog/item/$id');
                                } else if (v == 'delete') {
                                  unawaited(_deleteItemById(id, name));
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red.shade800),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ),
                );
              }),
          ],
        ),
      ),
    ),
    );
  }
}
