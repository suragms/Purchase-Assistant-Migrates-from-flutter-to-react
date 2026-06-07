import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'catalog_providers.dart';
import 'stock_providers.dart';

class ItemDetailBundle {
  const ItemDetailBundle({
    required this.catalogItem,
    required this.stockDetail,
    required this.activity,
    required this.tradePurchases,
    this.catalogError,
    this.stockError,
    this.activityError,
  });

  final Map<String, dynamic> catalogItem;
  final Map<String, dynamic> stockDetail;
  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> tradePurchases;
  final Object? catalogError;
  final Object? stockError;
  final Object? activityError;

  bool get hasAnyData =>
      catalogItem.isNotEmpty ||
      stockDetail.isNotEmpty ||
      activity.isNotEmpty;

  bool get allSectionsFailed =>
      catalogError != null &&
      stockError != null &&
      activityError != null &&
      !hasAnyData;
}

/// Parallel fetch for item detail. Keep this light: it is mounted whenever
/// `/catalog/item/:id` is opened.
final itemDetailBundleProvider =
    FutureProvider.autoDispose.family<ItemDetailBundle, String>((ref, itemId) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 45), keepAlive.close);
  ref.onDispose(timer.cancel);

  final session = ref.watch(sessionProvider);
  if (session == null) {
    return const ItemDetailBundle(
      catalogItem: {},
      stockDetail: {},
      activity: {},
      tradePurchases: [],
    );
  }

  // Re-fetch when staff/owner stock or catalog writes bust leaf providers.
  ref.watch(catalogItemDetailProvider(itemId));
  ref.watch(stockItemDetailProvider(itemId));
  ref.watch(stockItemActivityProvider(itemId));

  Object? catalogError;
  Map<String, dynamic> catalog = {};
  try {
    catalog = Map<String, dynamic>.from(
      await ref.read(catalogItemDetailProvider(itemId).future),
    );
  } catch (e) {
    catalogError = e;
  }

  Object? stockError;
  Map<String, dynamic> stock = {};
  try {
    stock = Map<String, dynamic>.from(
      await ref.read(stockItemDetailProvider(itemId).future),
    );
  } catch (e) {
    stockError = e;
  }

  Object? activityError;
  Map<String, dynamic> activity = {};
  try {
    activity = Map<String, dynamic>.from(
      await ref.read(stockItemActivityProvider(itemId).future),
    );
  } catch (e) {
    activityError = e;
  }

  return ItemDetailBundle(
    catalogItem: catalog,
    stockDetail: stock,
    activity: activity,
    tradePurchases: const [],
    catalogError: catalogError,
    stockError: stockError,
    activityError: activityError,
  );
});

/// Stock map for item detail sections — leaf provider (retry invalidates stock only).
final itemDetailStockProvider =
    Provider.autoDispose.family<AsyncValue<Map<String, dynamic>>, String>(
        (ref, itemId) {
  return ref.watch(stockItemDetailProvider(itemId));
});

/// Catalog map for item detail sections (leaf provider).
final itemDetailCatalogProvider =
    Provider.autoDispose.family<AsyncValue<Map<String, dynamic>>, String>(
        (ref, itemId) {
  return ref.watch(catalogItemDetailProvider(itemId));
});

/// Activity map for item detail timeline sections.
final itemDetailActivityProvider =
    Provider.autoDispose.family<AsyncValue<Map<String, dynamic>>, String>(
        (ref, itemId) {
  return ref.watch(stockItemActivityProvider(itemId));
});
