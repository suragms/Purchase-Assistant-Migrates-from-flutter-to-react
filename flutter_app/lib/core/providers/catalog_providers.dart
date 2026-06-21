import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import 'stock_list_exceptions.dart';

/// Default insights window: last 90 days (aligns with price intelligence default).
({String from, String to}) catalogInsightsDefaultRange() {
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: 90));
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return (from: iso(from), to: iso(to));
}

/// Kept alive — categories change rarely; avoids cold-load on every catalog open.
final itemCategoriesListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref
      .read(hexaApiProvider)
      .listItemCategories(businessId: session.primaryBusiness.id);
});

/// Kept alive so the purchase wizard never cold-loads catalog twice per session.
final catalogItemsListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref
      .read(hexaApiProvider)
      .listCatalogItems(businessId: session.primaryBusiness.id);
});

/// Per-category types (Category → Type → items) — derived from bulk index.
final categoryTypesListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, categoryId) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final index = await ref.watch(categoryTypesIndexProvider.future);
  return index
      .where((t) => t['category_id']?.toString() == categoryId)
      .toList();
});

/// Flat index: every type with `category_id` + `category_name` (quick-add, search).
final categoryTypesIndexProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listCategoryTypesIndex(
        businessId: session.primaryBusiness.id,
      );
});

/// Params: `itemId|from|to` for stable family identity.
final catalogItemInsightsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length != 3) return {};
  final itemId = parts[0];
  final from = parts[1];
  final to = parts[2];
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).catalogItemInsights(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        from: from,
        to: to,
      );
});

final categoryInsightsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length != 3) return {};
  final categoryId = parts[0];
  final from = parts[1];
  final to = parts[2];
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).categoryInsights(
        businessId: session.primaryBusiness.id,
        categoryId: categoryId,
        from: from,
        to: to,
      );
});

final catalogItemLinesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length != 3) return [];
  final itemId = parts[0];
  final from = parts[1];
  final to = parts[2];
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).catalogItemLines(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        from: from,
        to: to,
      );
});

final catalogVariantsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listCatalogVariants(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
});

final catalogItemDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    throw const StockListFetchBlockedException('api_gate');
  }
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  final row = await ref.read(hexaApiProvider).getCatalogItem(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return row;
});

/// Confirmed-trade aggregates per item in a category (server SSOT).
final categoryTradeSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, categoryId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).categoryTradeSummary(
        businessId: session.primaryBusiness.id,
        categoryId: categoryId,
      );
});

/// Latest trade price per supplier + last 5 landing prices (trade purchases only).
final catalogItemTradeSupplierPricesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).catalogItemTradeSupplierPrices(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
});

/// Key: `itemName|currentLanding` (landing may be empty). Name-based price intelligence.
final catalogItemPriceIntelProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final sep = key.indexOf('|');
  final name = sep < 0 ? key : key.substring(0, sep);
  final curStr = sep < 0 ? '' : key.substring(sep + 1);
  final cur = curStr.isEmpty ? null : double.tryParse(curStr);
  if (name.trim().length < 2) return {};
  try {
    return await ref.read(hexaApiProvider).priceIntelligence(
          businessId: session.primaryBusiness.id,
          item: name,
          currentPrice: cur,
          priceField: 'landing',
        );
  } catch (_) {
    return {};
  }
});
