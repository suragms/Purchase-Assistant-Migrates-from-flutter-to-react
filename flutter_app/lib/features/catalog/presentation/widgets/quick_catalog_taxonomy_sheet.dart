import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/search/catalog_fuzzy.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/form_feedback.dart';
import '../../catalog_taxonomy_utils.dart';

/// What the quick sheet should create.
enum QuickCatalogTaxonomyMode {
  /// New category; optional first subcategory in one step.
  categoryAndOptionalSub,

  /// New subcategory under an existing category.
  subcategoryOnly,
}

/// Opens a keyboard-safe sheet to create category / subcategory (staff + owner).
Future<CatalogTaxonomyCreateResult?> showQuickCatalogTaxonomySheet(
  BuildContext context, {
  QuickCatalogTaxonomyMode mode = QuickCatalogTaxonomyMode.categoryAndOptionalSub,
  String? preselectedCategoryId,
}) {
  return showHexaBottomSheet<CatalogTaxonomyCreateResult>(
    context: context,
    child: QuickCatalogTaxonomySheet(
      mode: mode,
      preselectedCategoryId: preselectedCategoryId,
    ),
  );
}

class QuickCatalogTaxonomySheet extends ConsumerStatefulWidget {
  const QuickCatalogTaxonomySheet({
    super.key,
    this.mode = QuickCatalogTaxonomyMode.categoryAndOptionalSub,
    this.preselectedCategoryId,
  });

  final QuickCatalogTaxonomyMode mode;
  final String? preselectedCategoryId;

  @override
  ConsumerState<QuickCatalogTaxonomySheet> createState() =>
      _QuickCatalogTaxonomySheetState();
}

class _QuickCatalogTaxonomySheetState
    extends ConsumerState<QuickCatalogTaxonomySheet> {
  final _categoryCtrl = TextEditingController();
  final _subcategoryCtrl = TextEditingController();
  String? _categoryId;
  bool _saving = false;
  bool _touched = false;

  bool get _subOnly =>
      widget.mode == QuickCatalogTaxonomyMode.subcategoryOnly;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.preselectedCategoryId;
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _subcategoryCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmSimilar(
    String title,
    String label,
    List<Map<String, dynamic>> similar,
  ) async {
    if (similar.isEmpty || !mounted) return true;
    final sample = similar
        .map((c) => c['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .take(2)
        .join('", "');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          sample.isEmpty
              ? 'A close name match exists. Create "$label" anyway?'
              : 'Close matches include "$sample". Create "$label" anyway?',
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Go back')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Create')),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;

    final catName = _subOnly ? null : _categoryCtrl.text.trim();
    final subName = _subcategoryCtrl.text.trim();
    final needsCat = !_subOnly && (catName == null || catName.isEmpty);
    final needsSub = _subOnly && subName.isEmpty;
    final needsCatPick = _subOnly && (_categoryId == null || _categoryId!.isEmpty);

    if (needsCat || needsSub || needsCatPick) {
      setState(() => _touched = true);
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(hexaApiProvider);
      final bid = session.primaryBusiness.id;

      if (!_subOnly) {
        final cats = await ref.read(itemCategoriesListProvider.future);
        final similar = catalogFuzzyRank(
          catName!,
          cats,
          (c) => c['name']?.toString() ?? '',
          minScore: 86,
          limit: 4,
        );
        if (!await _confirmSimilar(
          'Similar category exists',
          catName,
          similar,
        )) {
          return;
        }
        final created = await api.createItemCategory(
          businessId: bid,
          name: catName,
        );
        _categoryId = created['id']?.toString();
        if (_categoryId == null || _categoryId!.isEmpty) {
          throw Exception('Category created but id missing');
        }
      }

      String? typeId;
      String? typeName;
      if (subName.isNotEmpty) {
        final types =
            typesForCategory(
              await ref.read(categoryTypesIndexProvider.future),
              _categoryId!,
            );
        final similar = catalogFuzzyRank(
          subName,
          types,
          (t) => t['name']?.toString() ?? '',
          minScore: 86,
          limit: 4,
        );
        if (!await _confirmSimilar(
          'Similar subcategory exists',
          subName,
          similar,
        )) {
          return;
        }
        final type = await api.createCategoryType(
          businessId: bid,
          categoryId: _categoryId!,
          name: subName,
        );
        typeId = type['id']?.toString();
        typeName = type['name']?.toString() ?? subName;
      }

      invalidateCatalogTaxonomy(ref, categoryId: _categoryId);

      if (!mounted) return;
      final resolvedCatName = _subOnly
          ? (await ref.read(itemCategoriesListProvider.future))
              .cast<Map<String, dynamic>>()
              .where((c) => c['id']?.toString() == _categoryId)
              .map((c) => c['name']?.toString())
              .whereType<String>()
              .firstOrNull
          : catName;

      Navigator.of(context).pop(
        CatalogTaxonomyCreateResult(
          categoryId: _categoryId!,
          categoryName: resolvedCatName ?? catName ?? 'Category',
          typeId: typeId,
          typeName: typeName,
        ),
      );
    } on DioException catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: _save);
      }
    } catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: _save);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final errCat = _touched && !_subOnly && _categoryCtrl.text.trim().isEmpty;
    final errSub = _touched && _subOnly && _subcategoryCtrl.text.trim().isEmpty;
    final errPick =
        _touched && _subOnly && (_categoryId == null || _categoryId!.isEmpty);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _subOnly ? 'New subcategory' : 'New category',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            _subOnly
                ? 'Pick a category, then name the subcategory (type).'
                : 'Add a category. Optionally add the first subcategory now.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_subOnly)
            catsAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (_, __) => Text(
                'Could not load categories',
                style: TextStyle(color: HexaColors.loss, fontSize: 13),
              ),
              data: (cats) {
                if (cats.isEmpty) {
                  return Text(
                    'Create a category first from this screen.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    errorText: errPick ? 'Select a category' : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(
                        value: c['id']?.toString(),
                        child: Text(c['name']?.toString() ?? '—'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _categoryId = v),
                );
              },
            )
          else
            TextField(
              controller: _categoryCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Category name',
                hintText: 'e.g. Rice, Oil',
                errorText: errCat ? 'Enter a name' : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _subcategoryCtrl,
            autofocus: _subOnly,
            textCapitalization: TextCapitalization.words,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: _subOnly ? 'Subcategory name' : 'Subcategory (optional)',
              hintText: 'e.g. Biriyani rice',
              errorText: errSub ? 'Enter a name' : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_subOnly ? 'Create subcategory' : 'Create'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
