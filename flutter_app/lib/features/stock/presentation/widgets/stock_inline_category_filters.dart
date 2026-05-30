import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/widgets/hexa_elevated_autocomplete.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../stock_period_utils.dart';

/// Category + subcategory filters on the stock **All** tab (outside Filters sheet).
class StockInlineCategoryFilters extends ConsumerWidget {
  const StockInlineCategoryFilters({
    super.key,
    required this.subcategoryController,
    this.onFiltersCleared,
  });

  final TextEditingController subcategoryController;
  final VoidCallback? onFiltersCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final typesAsync = ref.watch(categoryTypesIndexProvider);

    final hasInline = q.q.isNotEmpty ||
        q.category.isNotEmpty ||
        q.subcategory.isNotEmpty ||
        q.supplier.isNotEmpty ||
        countOperationalActiveFilters(q, op) > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HexaOp.pageGutter,
        0,
        HexaOp.pageGutter,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          catsAsync.when(
            loading: () => const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final names = [
                for (final c in cats)
                  if ((c['name'] ?? '').toString().trim().isNotEmpty)
                    (c['name'] ?? '').toString().trim(),
              ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              return DropdownButtonFormField<String>(
                initialValue: q.category.isEmpty ? null : q.category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('All categories')),
                  for (final n in names)
                    DropdownMenuItem(value: n, child: Text(n)),
                ],
                onChanged: (v) {
                  ref.read(stockListQueryProvider.notifier).state =
                      ref.read(stockListQueryProvider).copyWith(
                            category: v ?? '',
                            subcategory: '',
                            page: 1,
                          );
                  subcategoryController.clear();
                },
              );
            },
          ),
          const SizedBox(height: 6),
          typesAsync.when(
            loading: () => TextField(
              controller: subcategoryController,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Subcategory',
                isDense: true,
                filled: true,
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (types) {
              final cat = q.category.trim().toLowerCase();
              final options = <String>[];
              for (final t in types) {
                final name = (t['name'] ?? '').toString().trim();
                if (name.isEmpty) continue;
                final cname =
                    (t['category_name'] ?? '').toString().trim().toLowerCase();
                if (cat.isNotEmpty && cname != cat) continue;
                options.add(name);
              }
              options
                  .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              return Autocomplete<String>(
                initialValue: q.subcategory.isEmpty
                    ? null
                    : TextEditingValue(text: q.subcategory),
                optionsViewBuilder: (context, onSelected, options) {
                  return hexaElevatedAutocompleteOptions<String>(
                    context,
                    onSelected,
                    options,
                    label: (v) => v,
                  );
                },
                optionsBuilder: (text) {
                  final needle = text.text.trim().toLowerCase();
                  if (needle.isEmpty) return options.take(12);
                  return options
                      .where((o) => o.toLowerCase().contains(needle))
                      .take(12);
                },
                onSelected: (v) {
                  subcategoryController.text = v;
                  ref.read(stockListQueryProvider.notifier).state =
                      ref.read(stockListQueryProvider).copyWith(
                            subcategory: v,
                            page: 1,
                          );
                },
                fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
                  if (ctrl.text != subcategoryController.text) {
                    ctrl.text = subcategoryController.text;
                  }
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    onChanged: (v) {
                      subcategoryController.text = v;
                      if (v.trim().isEmpty &&
                          ref
                              .read(stockListQueryProvider)
                              .subcategory
                              .isNotEmpty) {
                        ref.read(stockListQueryProvider.notifier).state =
                            ref.read(stockListQueryProvider).copyWith(
                                  subcategory: '',
                                  page: 1,
                                );
                      }
                    },
                    onSubmitted: (v) {
                      ref.read(stockListQueryProvider.notifier).state =
                          ref.read(stockListQueryProvider).copyWith(
                                subcategory: v.trim(),
                                page: 1,
                              );
                    },
                    decoration: InputDecoration(
                      labelText: 'Subcategory',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: ctrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                ctrl.clear();
                                subcategoryController.clear();
                                ref
                                        .read(stockListQueryProvider.notifier)
                                        .state =
                                    ref.read(stockListQueryProvider).copyWith(
                                          subcategory: '',
                                          page: 1,
                                        );
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
              );
            },
          ),
          if (hasInline)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  final period = ref.read(stockPagePeriodProvider);
                  applyStockPagePeriod(ref, period);
                  ref.read(stockOperationalFiltersProvider.notifier).state =
                      const StockOperationalFilters();
                  subcategoryController.clear();
                  onFiltersCleared?.call();
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Clear filters'),
              ),
            ),
        ],
      ),
    );
  }
}
