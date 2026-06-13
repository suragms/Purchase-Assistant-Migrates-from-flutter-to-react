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

/// Parallel fetch for item detail. Keep this light: it is mounted whenever
/// `/catalog/item/:id` is opened.
///
/// Do not [ref.watch] leaf detail providers here — that caused reload loops when
/// stock list saves invalidated [stockItemDetailProvider].
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
  Object? activityError;
  Map<String, dynamic> activity = {};

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
    () async {
      try {
        activity = Map<String, dynamic>.from(
          await _fetchWithRetry(
            () => ref.read(stockItemActivityProvider(itemId).future),
          ),
        );
      } catch (e, st) {
        logSilencedApiError(e, st);
        activityError = e;
      }
    }(),
  ]);

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
