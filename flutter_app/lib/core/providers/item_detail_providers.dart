import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../errors/user_facing_errors.dart';
import 'catalog_providers.dart';
import 'stock_providers.dart';

Future<T> _fetchWithRetry<T>(Future<T> Function() load) async {
  for (var i = 0; i < 3; i++) {
    try {
      return await load();
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (i == 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
    }
  }
  throw StateError('Unreachable');
}

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

/// Parallel fetch for item detail warm-up (catalog + stock only).
/// Activity / purchases load lazily when their tabs open.
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

  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    return const ItemDetailBundle(
      catalogItem: {},
      stockDetail: {},
      activity: {},
      tradePurchases: [],
    );
  }

  Object? catalogError;
  Map<String, dynamic> catalog = {};
  Object? stockError;
  Map<String, dynamic> stock = {};

  await Future.wait<void>([
    () async {
      try {
        catalog = Map<String, dynamic>.from(
          await _fetchWithRetry(
            () => ref.read(catalogItemDetailProvider(itemId).future),
          ),
        );
      } catch (e, st) {
        logSilencedApiError(e, st);
        catalogError = e;
      }
    }(),
    () async {
      try {
        stock = Map<String, dynamic>.from(
          await _fetchWithRetry(
            () => ref.read(stockItemDetailProvider(itemId).future),
          ),
        );
      } catch (e, st) {
        logSilencedApiError(e, st);
        stockError = e;
      }
    }(),
  ]);

  return ItemDetailBundle(
    catalogItem: catalog,
    stockDetail: stock,
    activity: const {},
    tradePurchases: const [],
    catalogError: catalogError,
    stockError: stockError,
  );
});

/// Item analytics intelligence — fixed 30-day window (not tied to stock list query).
final itemStockIntelligenceProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) return {};
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final start = end.subtract(const Duration(days: 29));
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return ref.read(hexaApiProvider).getStockIntelligence(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        periodStart: iso(start),
        periodEnd: iso(end),
      );
});

/// Stock map for item detail sections — merges optimistic patches (no flash on save).
final itemDetailStockProvider =
    Provider.autoDispose.family<AsyncValue<Map<String, dynamic>>, String>(
        (ref, itemId) {
  final async = ref.watch(stockItemDetailProvider(itemId));
  final patch = ref.watch(stockItemDetailPatchProvider(itemId));
  if (patch.isEmpty) return async;
  return async.when(
    data: (data) => AsyncValue.data({...data, ...patch}),
    loading: () => AsyncValue.data(Map<String, dynamic>.from(patch)),
    error: (e, st) => async.hasValue
        ? AsyncValue.data({...async.requireValue, ...patch})
        : AsyncValue.data(Map<String, dynamic>.from(patch)),
  );
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
