import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Owner dashboard: counts per delivery_status from API.
final deliveryPipelineProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).fetchDeliveryPipeline(
        businessId: session.primaryBusiness.id,
      );
});

/// Undelivered PUR bills across pipeline stages (same as staff home KPI).
int deliveryPipelinePendingCount(Map<String, dynamic>? pipeline) {
  if (pipeline == null || pipeline.isEmpty) return 0;
  return ((pipeline['pending'] as num?)?.toInt() ?? 0) +
      ((pipeline['dispatched'] as num?)?.toInt() ?? 0) +
      ((pipeline['in_transit'] as num?)?.toInt() ?? 0) +
      ((pipeline['arrived'] as num?)?.toInt() ?? 0) +
      ((pipeline['staff_verifying'] as num?)?.toInt() ?? 0) +
      ((pipeline['staff_verified'] as num?)?.toInt() ?? 0) +
      ((pipeline['partial'] as num?)?.toInt() ?? 0);
}
