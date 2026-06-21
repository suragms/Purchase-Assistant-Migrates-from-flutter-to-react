import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/catalog_providers.dart';
import '../../core/providers/contacts_hub_provider.dart';

/// Types belonging to [categoryId] from the flat category-types index.
List<Map<String, dynamic>> typesForCategory(
  List<Map<String, dynamic>> index,
  String categoryId,
) {
  return index
      .where((t) => t['category_id']?.toString() == categoryId)
      .toList();
}

/// Count subcategories for [categoryId] from the flat index.
int typeCountForCategory(List<Map<String, dynamic>> index, String categoryId) {
  var n = 0;
  for (final t in index) {
    if (t['category_id']?.toString() == categoryId) n++;
  }
  return n;
}

/// Bust all category / subcategory pickers after a taxonomy write.
void invalidateCatalogTaxonomy(WidgetRef ref, {String? categoryId}) {
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(categoryTypesIndexProvider);
  ref.invalidate(catalogItemsListProvider);
  ref.invalidate(contactsCategoriesProvider);
  if (categoryId != null && categoryId.isNotEmpty) {
    ref.invalidate(categoryTypesListProvider(categoryId));
  }
}

/// Result of creating category and optional subcategory (type).
class CatalogTaxonomyCreateResult {
  const CatalogTaxonomyCreateResult({
    required this.categoryId,
    required this.categoryName,
    this.typeId,
    this.typeName,
  });

  final String categoryId;
  final String categoryName;
  final String? typeId;
  final String? typeName;
}
