import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import 'analytics_kpi_provider.dart' show analyticsDateRangeProvider;

/// Shared trade report rows for Home shell + Analytics breakdown tabs.
class TradeReportSnapshot {
  const TradeReportSnapshot({
    required this.types,
    required this.suppliers,
    required this.items,
  });

  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> items;

  static const empty = TradeReportSnapshot(
    types: [],
    suppliers: [],
    items: [],
  );
}

typedef TradeReportRangeKey = ({String from, String to});

TradeReportRangeKey tradeReportRangeKeyForAnalytics(Ref ref) {
  final range = ref.watch(analyticsDateRangeProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  return (from: fmt.format(range.from), to: fmt.format(range.to));
}

const Duration _tradeReportSnapshotKeepAlive = Duration(minutes: 3);

final Map<String, Future<TradeReportSnapshot>> _tradeReportInflight = {};

Future<TradeReportSnapshot> fetchTradeReportSnapshot(
  Ref ref,
  TradeReportRangeKey range,
) async {
  final session = ref.read(activeSessionProvider);
  if (session == null) return TradeReportSnapshot.empty;
  final dedupeKey = '${session.primaryBusiness.id}|${range.from}|${range.to}';
  return _tradeReportInflight.putIfAbsent(
    dedupeKey,
    () async {
      final link = ref.keepAlive();
      final timer = Timer(_tradeReportSnapshotKeepAlive, link.close);
      ref.onDispose(timer.cancel);
      final api = ref.read(hexaApiProvider);
      final bid = session.primaryBusiness.id;
      try {
        final out = await Future.wait([
          api.tradeReportTypes(
            businessId: bid,
            from: range.from,
            to: range.to,
          ),
          api.tradeReportSuppliers(
            businessId: bid,
            from: range.from,
            to: range.to,
          ),
          api.tradeReportItems(
            businessId: bid,
            from: range.from,
            to: range.to,
          ),
        ]).timeout(const Duration(seconds: 32));
        return TradeReportSnapshot(
          types: List<Map<String, dynamic>>.from(out[0]),
          suppliers: List<Map<String, dynamic>>.from(out[1]),
          items: List<Map<String, dynamic>>.from(out[2]),
        );
      } on TimeoutException {
        return TradeReportSnapshot.empty;
      } finally {
        _tradeReportInflight.remove(dedupeKey);
      }
    },
  );
}

/// Single SSOT fetch keyed by analytics date range (Home + Reports share this).
final tradeReportSnapshotProvider =
    FutureProvider.autoDispose<TradeReportSnapshot>((ref) async {
  final range = tradeReportRangeKeyForAnalytics(ref);
  return fetchTradeReportSnapshot(ref, range);
});

void bustTradeReportSnapshotInflight() {
  _tradeReportInflight.clear();
}
