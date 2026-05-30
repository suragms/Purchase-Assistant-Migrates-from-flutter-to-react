import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import 'analytics_kpi_provider.dart';

final reportsPeriodComparisonProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return {};
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportPeriodComparison(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final reportsMovementSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return {};
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportMovementSummary(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});
