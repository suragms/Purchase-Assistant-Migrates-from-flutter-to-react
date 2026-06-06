import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/search/search_highlight.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/business_write_surface_listener.dart';
import 'widgets/quick_catalog_taxonomy_sheet.dart';

/// Category list (layer 1). Subcategories and items live on deeper routes.
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
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

  Future<void> _editCategory(BuildContext context, String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).updateItemCategory(
            businessId: session.primaryBusiness.id,
            categoryId: id,
            name: ctrl.text.trim(),
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _deleteCategory(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete “$name”? It must have no items.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteItemCategory(
            businessId: session.primaryBusiness.id,
            categoryId: id,
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);

    return BusinessWriteSurfaceListener(
      onRefresh: (ref, _) {
        ref.invalidate(itemCategoriesListProvider);
        ref.invalidate(catalogItemsListProvider);
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Catalog'),
        actions: [
          IconButton(
            tooltip: 'Quick categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => context.push('/catalog/taxonomy'),
          ),
          IconButton(
            tooltip: 'Stock list',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.go('/stock'),
          ),
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/barcode/scan'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showQuickCatalogTaxonomySheet(context);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search categories (fuzzy)',
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
              onChanged: (_) {},
            ),
          ),
          if (_searchQuery.trim().isNotEmpty)
            async.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                final q = _searchQuery.trim();
                final sug = catalogFuzzyRank(
                  q,
                  list,
                  (c) => c['name']?.toString() ?? '',
                  minScore: q.length <= 1 ? 10.0 : 38,
                  limit: 6,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final c in sug)
                          ActionChip(
                            label: Text(c['name']?.toString() ?? ''),
                            onPressed: () {
                              final id = c['id']?.toString();
                              if (id != null) context.push('/catalog/category/$id');
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const ListSkeleton(),
              error: (_, __) => FriendlyLoadError(
                onRetry: () {
                  ref.invalidate(itemCategoriesListProvider);
                  ref.invalidate(catalogItemsListProvider);
                },
              ),
              data: (list) {
                final items = itemsAsync.maybeWhen(data: (x) => x, orElse: () => <Map<String, dynamic>>[]);
                final q = _searchQuery.trim();
                final display = q.isEmpty
                    ? list
                    : catalogFuzzyRank(
                        q,
                        list,
                        (c) => c['name']?.toString() ?? '',
                        minScore: q.length <= 1 ? 10.0 : 38,
                        limit: 500,
                      );

                final desktop = context.isDesktopLayout;
                final gridCols = desktop ? 2 : 1;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(itemCategoriesListProvider);
                    ref.invalidate(catalogItemsListProvider);
                    await ref.read(itemCategoriesListProvider.future);
                    await ref.read(catalogItemsListProvider.future);
                  },
                  child: display.isEmpty
                      ? ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 100),
                          children: [
                            Icon(Icons.folder_outlined,
                                size: 48, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 16),
                            Text(
                              list.isEmpty ? 'No categories yet' : 'No matches',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              list.isEmpty
                                  ? 'Add a category, then subcategories and items — all from this catalog.'
                                  : 'Try a different spelling or clear search.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        )
                      : HexaResponsiveCenter(
                          maxWidth: desktop ? 1100 : HexaResponsive.maxContentWidth,
                          padding: EdgeInsets.zero,
                          child: GridView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: gridCols,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: desktop ? 3.6 : 4.2,
                            ),
                            itemCount: display.length,
                            itemBuilder: (context, i) {
                              final c = display[i];
                              final id = c['id']?.toString() ?? '';
                              final name = c['name']?.toString() ?? '';
                              final itemCount = items
                                  .where(
                                    (it) =>
                                        it['category_id']?.toString() == id,
                                  )
                                  .length;
                              final subN = ref.watch(
                                categoryTypesListProvider(id).select(
                                  (a) => a.valueOrNull?.length ?? -1,
                                ),
                              );
                              final subCount = subN < 0 ? 0 : subN;
                              return Card(
                                margin: EdgeInsets.zero,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.85),
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () =>
                                      context.push('/catalog/category/$id'),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: HexaColors.primaryMid
                                              .withValues(alpha: 0.2),
                                          foregroundColor: HexaColors.primaryMid,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      backgroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primaryContainer
                                                              .withValues(
                                                                alpha: 0.4,
                                                              ),
                                                    ),
                                                  ),
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$subCount subcategories · $itemCount items',
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
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              _editCategory(context, id, name);
                                            }
                                            if (v == 'del') {
                                              _deleteCategory(context, id, name);
                                            }
                                          },
                                          itemBuilder: (ctx) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Rename'),
                                            ),
                                            PopupMenuItem(
                                              value: 'del',
                                              child: Text('Delete'),
                                            ),
                                          ],
                                        ),
                                        const Icon(Icons.chevron_right_rounded),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}
