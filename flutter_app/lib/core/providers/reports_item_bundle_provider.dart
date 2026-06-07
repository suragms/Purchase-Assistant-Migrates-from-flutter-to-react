import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';

/// Backend SSOT for Reports → item drill-down (properties + period purchases).
final reportsItemBundleProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, catalogItemId) async {
  ref.keepAlive();
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final range = ref.watch(analyticsDateRangeProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final api = ref.read(hexaApiProvider);
  return api.reportsItemBundle(
    businessId: session.primaryBusiness.id,
    catalogItemId: catalogItemId,
    from: fmt.format(range.from),
    to: fmt.format(range.to),
    limit: 80,
  );
});
