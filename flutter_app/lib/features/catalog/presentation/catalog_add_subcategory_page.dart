import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../catalog_taxonomy_utils.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/form_feedback.dart';
import '../../../shared/widgets/keyboard_safe_form_viewport.dart';

/// Full-screen create subcategory (category type).
class CatalogAddSubcategoryPage extends ConsumerStatefulWidget {
  const CatalogAddSubcategoryPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CatalogAddSubcategoryPage> createState() =>
      _CatalogAddSubcategoryPageState();
}

class _CatalogAddSubcategoryPageState
    extends ConsumerState<CatalogAddSubcategoryPage> {
  final _name = TextEditingController();
  bool _saving = false;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    // Avoid showing a previous screen's error (e.g. phone validation) on this route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      setState(() => _touched = true);
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final index = await ref.read(categoryTypesIndexProvider.future);
      final types = typesForCategory(index, widget.categoryId);
      final similar = catalogFuzzyRank(
        n,
        types,
        (t) => t['name']?.toString() ?? '',
        minScore: 86,
        limit: 4,
      );
      if (similar.isNotEmpty && mounted) {
        final sample = similar
            .map((t) => t['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .take(2)
            .join('", "');
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar subcategory exists'),
            content: Text(
              sample.isEmpty
                  ? 'A close name match exists. Create "$n" anyway?'
                  : 'Close matches include "$sample". Create "$n" anyway?',
            ),
            actions: [
              TextButton(onPressed: () => ctx.pop(false), child: const Text('Go back')),
              FilledButton(onPressed: () => ctx.pop(true), child: const Text('Create')),
            ],
          ),
        );
        if (go != true) return;
      }
    } catch (_) {}
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).createCategoryType(
            businessId: session.primaryBusiness.id,
            categoryId: widget.categoryId,
            name: n,
          );
      invalidateCatalogTaxonomy(ref, categoryId: widget.categoryId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subcategory created')),
        );
        context.pop(true);
      }
    } on DioException catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } catch (e) {
      if (mounted) {
        showRetryableErrorSnackBar(context, e, onRetry: () {
          if (context.mounted) _create();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _touched && _name.text.trim().isEmpty;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New subcategory'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving ? null : () => context.pop(false),
          ),
        ),
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, c) {
                final minFields = math.max(200.0, c.maxHeight - 200);
                return KeyboardSafeFormViewport(
                  dismissKeyboardOnTap: false,
                  horizontalPadding: 16,
                  topPadding: 16,
                  minFieldsHeight: c.hasBoundedHeight ? minFields : 200,
                  fields: TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Biriyani rice',
                      errorText: err ? 'Enter a name' : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: err
                              ? HexaColors.loss
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (_touched) setState(() {});
                    },
                  ),
                  footer: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => context.pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _create,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
