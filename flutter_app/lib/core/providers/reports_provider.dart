import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/hexa_api.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../auth/provider_api_guard.dart';
import '../errors/user_facing_errors.dart';
import '../models/trade_purchase_models.dart';
import '../reporting/trade_report_aggregate.dart';
import '../services/offline_store.dart';
import '../utils/report_date_params.dart';
import '../../features/shell/shell_branch_provider.dart';
import 'api_degraded_provider.dart';
import 'analytics_kpi_provider.dart';
import 'connectivity_provider.dart' show isOfflineResult;

final Map<String, Future<List<TradePurchase>>> _reportsPurchasesInflight = {};
DateTime? _reportsInflightLastBustAt;

const int _reportsInflightBustCooldownMs = 3000;

/// Set when purchases/analytics change off-tab so Reports live-fetches on next open.
final reportsPurchasesNeedsLiveFetchProvider = StateProvider<bool>((ref) => false);

void markReportsPurchasesNeedsLiveFetch(dynamic ref) {
  ref.read(reportsPurchasesNeedsLiveFetchProvider.notifier).state = true;
  bustReportsPurchasesInflight();
}

void clearReportsPurchasesNeedsLiveFetch(dynamic ref) {
  ref.read(reportsPurchasesNeedsLiveFetchProvider.notifier).state = false;
}

void bustReportsPurchasesInflight() {
  final now = DateTime.now();
  if (_reportsInflightLastBustAt != null &&
      now.difference(_reportsInflightLastBustAt!).inMilliseconds <
          _reportsInflightBustCooldownMs) {
    return;
  }
  _reportsInflightLastBustAt = now;
  _reportsPurchasesInflight.clear();
}

bool _isNonRetryableNetworkError(Object e) {
  if (e is DioException) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.cancel;
  }
  return false;
}

String _reportsLiveErrMsg(Object e) {
  if (e is DioException) {
    final sc = e.response?.statusCode;
    if (sc == 401 || sc == 403) {
      return 'Session expired — sign in again';
    }
  }
  return userFacingError(e);
}

class ReportsPurchasePayload {
  ReportsPurchasePayload({
    required this.items,
    this.fromLiveFetch = false,
    this.liveFetchError,
  });

  final List<TradePurchase> items;
  final bool fromLiveFetch;
  final String? liveFetchError;

  static ReportsPurchasePayload empty() =>
      ReportsPurchasePayload(items: const []);
}

/// Same inclusive local-day window as Home [home_dashboard_provider] filtering.
bool _reportsPurchaseInInclusiveRange(
  DateTime purchaseDate,
  DateTime from,
  DateTime toInclusive,
) {
  final pd = DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day);
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(toInclusive.year, toInclusive.month, toInclusive.day);
  return !pd.isBefore(a) && !pd.isAfter(b);
}

/// When `purchase_from` / `purchase_to` return no rows but `/reports/trade-summary`
/// shows deals in-range, re-fetch without date query params and filter locally
/// (mirrors Home trade list behavior — fixes timezone / API edge mismatches).
Future<({List<TradePurchase> items, List<Map<String, dynamic>> raw})?>
    _tryReportsPurchasesFallbackUnfiltered({
  required HexaApi api,
  required String bid,
  required String fromStr,
  required String toStr,
  required ({DateTime from, DateTime to}) range,
}) async {
  try {
    final summary = await api.tradePurchaseSummary(
      businessId: bid,
      from: fromStr,
      to: toStr,
      tzOffsetMinutes: localTzOffsetMinutes,
    );
    final dr = summary['deals'];
    final deals = dr is int ? dr : int.tryParse('$dr') ?? 0;
    if (deals <= 0) return null;
  } catch (_) {
    // Summary failed — still try a bounded unfiltered scan.
  }

  final fromD = DateTime(range.from.year, range.from.month, range.from.day);
  final toD = DateTime(range.to.year, range.to.month, range.to.day);
  final aggregated = <Map<String, dynamic>>[];
  for (var offset = 0; offset < 50000; offset += 50) {
    final page = await api.listTradePurchases(
      businessId: bid,
      limit: 50,
      offset: offset,
      status: 'all',
    );
    if (page.isEmpty) break;
    aggregated.addAll(page);
    if (page.length < 50) break;
  }
  final items = <TradePurchase>[];
  final inRangeRaw = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final e in aggregated) {
    try {
      final p = TradePurchase.fromJson(Map<String, dynamic>.from(e));
      if (p.id.isEmpty) continue;
      if (!_reportsPurchaseInInclusiveRange(p.purchaseDate, fromD, toD)) {
        continue;
      }
      if (seen.add(p.id)) {
        items.add(p);
        inRangeRaw.add(Map<String, dynamic>.from(e));
      }
    } catch (_) {}
  }
  if (items.isEmpty) return null;
  return (items: items, raw: inRangeRaw);
}

List<TradePurchase>? _decodePurchasesJson(String? js) {
  if (js == null || js.isEmpty) return null;
  try {
    final list = jsonDecode(js) as List<dynamic>;
    final out = <TradePurchase>[];
    for (final e in list) {
      if (e is! Map) continue;
      try {
        out.add(TradePurchase.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Trade purchase rows for Reports use [analyticsDateRangeProvider] (local calendar
/// `from`/`to` as `yyyy-MM-dd`) and the API `purchase_from` / `purchase_to` filters
/// on **purchase_date**, same window as Home analytics when that provider is shared.
final reportsPurchasesHiveCacheProvider =
    Provider.autoDispose<List<TradePurchase>?>((ref) {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return null;
  final df = DateFormat('yyyy-MM-dd');
  final fromStr = df.format(range.from);
  final toStr = df.format(range.to);
  final raw = OfflineStore.getReportsTradePurchasesJson(
    session.primaryBusiness.id,
    fromStr,
    toStr,
  );
  return _decodePurchasesJson(raw);
});

Future<List<TradePurchase>> _loadReportsPurchases(Ref ref) async {
  final session = ref.read(activeSessionProvider);
  final range = ref.read(analyticsDateRangeProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final df = DateFormat('yyyy-MM-dd');
  final fromStr = df.format(range.from);
  final toStr = df.format(range.to);
  final key = '$bid|$fromStr|$toStr';

  Future<List<TradePurchase>> work() async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt == 0) {
          final conn = await Connectivity().checkConnectivity();
          if (isOfflineResult(conn)) {
            throw DioException(
              requestOptions: RequestOptions(path: '/v1/trade-purchases'),
              type: DioExceptionType.connectionError,
              message: 'No internet connection',
            );
          }
        }
        final aggregated = <Map<String, dynamic>>[];
        for (var offset = 0;; offset += 50) {
          // [Bug 5 fix] Hard timeout on each page so a cold/unreachable Render
          // host can never hang the Reports page forever — we just fall back to
          // cached data + a Retry banner.
          final page = await api
              .listTradePurchases(
                businessId: bid,
                limit: 50,
                offset: offset,
                status: 'all',
                purchaseFrom: fromStr,
                purchaseTo: toStr,
              )
              .timeout(const Duration(seconds: 10));
          if (page.isEmpty) break;
          aggregated.addAll(page);
          if (page.length < 50) break;
        }
        final items = <TradePurchase>[];
        final seen = <String>{};
        for (final e in aggregated) {
          try {
            final p = TradePurchase.fromJson(Map<String, dynamic>.from(e));
            if (p.id.isEmpty) continue;
            if (seen.add(p.id)) items.add(p);
          } catch (_) {}
        }
        if (aggregated.isNotEmpty && items.isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[Reports] parse miss: ${aggregated.length} raw rows for '
              '$fromStr..$toStr — falling back to cache/empty',
            );
          }
          final fb = await _tryReportsPurchasesFallbackUnfiltered(
            api: api,
            bid: bid,
            fromStr: fromStr,
            toStr: toStr,
            range: range,
          );
          if (fb != null) {
            await OfflineStore.cacheReportsTradePurchasesJson(
              bid,
              fromStr,
              toStr,
              jsonEncode(fb.raw),
            );
            return fb.items;
          }
          return const [];
        }
        if (kDebugMode) {
          debugPrint(
            '[Reports] Fetching range: $fromStr → $toStr, key: $key; fetched ${items.length} purchases',
          );
        }
        if (items.isEmpty) {
          if (kDebugMode) {
            debugPrint('[REPORTS] empty — running unfiltered fallback');
          }
          final fb = await _tryReportsPurchasesFallbackUnfiltered(
            api: api,
            bid: bid,
            fromStr: fromStr,
            toStr: toStr,
            range: range,
          );
          if (fb != null) {
            await OfflineStore.cacheReportsTradePurchasesJson(
              bid,
              fromStr,
              toStr,
              jsonEncode(fb.raw),
            );
            return fb.items;
          }
        }
        await OfflineStore.cacheReportsTradePurchasesJson(
          bid,
          fromStr,
          toStr,
          jsonEncode(aggregated),
        );
        return items;
      } catch (e) {
        lastErr = e;
        if (_isNonRetryableNetworkError(e)) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 280 * (attempt + 1)));
      }
    }
    if (kDebugMode && lastErr != null) {
      debugPrint('[Reports] fetch failed after retries: $lastErr');
    }
    return const [];
  }

  return _reportsPurchasesInflight.putIfAbsent(
    key,
    () => work().whenComplete(() {
      Future<void>.delayed(
        const Duration(milliseconds: _reportsInflightBustCooldownMs),
        () => _reportsPurchasesInflight.remove(key),
      );
    }),
  );
}

/// Live `/trade-purchases` pages for the current [analyticsDateRangeProvider],
/// regardless of shell tab — used by scheduled WhatsApp share and should stay
/// consistent with [reportsPurchasesPayloadProvider] network error handling.
Future<ReportsPurchasePayload> fetchReportsPurchasesLiveForAnalytics(
  Ref ref,
) async {
  final session = ref.read(activeSessionProvider);
  if (session == null) return ReportsPurchasePayload.empty();
  try {
    final list = await _loadReportsPurchases(ref);
    return ReportsPurchasePayload(items: list, fromLiveFetch: true);
  } catch (e) {
    if (e is DioException && (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
      try {
        ref.read(apiDegradedProvider.notifier).notifyDegraded(
              'Session issue while loading reports. Please refresh or sign in again if needed.',
            );
      } catch (_) {}
    }
    final cached = ref.read(reportsPurchasesHiveCacheProvider);
    if (cached != null && cached.isNotEmpty) {
      return ReportsPurchasePayload(
        items: cached,
        fromLiveFetch: false,
        liveFetchError: _reportsLiveErrMsg(e),
      );
    }
    return ReportsPurchasePayload(
      items: const [],
      fromLiveFetch: false,
      liveFetchError: _reportsLiveErrMsg(e),
    );
  }
}

/// SSOT: full `/trade-purchases` rows for Reports (Hive fallback on failure).
final reportsPurchasesPayloadProvider =
    FutureProvider.autoDispose<ReportsPurchasePayload>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(t.cancel);
  if (providerSkipApi(ref)) return ReportsPurchasePayload.empty();
  final session = ref.watch(activeSessionProvider);
  ref.watch(analyticsDateRangeProvider);
  final branch = ref.watch(shellCurrentBranchProvider);
  final needsLive = ref.watch(reportsPurchasesNeedsLiveFetchProvider);
  if (session == null) return ReportsPurchasePayload.empty();

  // IndexedStack mounts Reports off-screen; use Hive only until the user opens Reports.
  if (branch != ShellBranch.reports && !needsLive) {
    final hive = ref.watch(reportsPurchasesHiveCacheProvider);
    return ReportsPurchasePayload(
      items: hive ?? const [],
      fromLiveFetch: false,
    );
  }

  final payload = await fetchReportsPurchasesLiveForAnalytics(ref);
  // Clear stale flag after this fetch completes (not during provider init).
  unawaited(
    Future<void>.microtask(() => clearReportsPurchasesNeedsLiveFetch(ref)),
  );
  return payload;
});

/// Merged purchase list for instant UI: completed payload, else in-flight
/// previous value, else Hive cache — avoids false empty while reloading.
final reportsPurchasesMergedProvider =
    Provider.autoDispose<List<TradePurchase>>((ref) {
  final async = ref.watch(reportsPurchasesPayloadProvider);
  final hive = ref.watch(reportsPurchasesHiveCacheProvider);
  return async.maybeWhen(
    data: (payload) => payload.items,
    orElse: () => async.valueOrNull?.items ?? hive ?? const [],
  );
});

/// Single aggregate engine input → [TradeReportAgg] (all classified lines).
final reportsAggregateProvider = Provider.autoDispose<TradeReportAgg>((ref) {
  return buildTradeReportAgg(ref.watch(reportsPurchasesMergedProvider));
});
