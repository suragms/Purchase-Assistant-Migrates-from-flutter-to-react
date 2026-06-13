import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart'
    show activeSessionProvider, hexaApiProvider;
import '../json_coerce.dart';
import 'home_dashboard_provider.dart'
    show homeDashboardDataProvider, homeTabHasOperationalBundle;

/// Owner dashboard: counts per delivery_status from API.
final deliveryPipelineProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (providerSkipApi(ref)) return {};
  if (homeTabHasOperationalBundle(ref)) {
    return Map<String, dynamic>.from(
      ref.watch(homeDashboardDataProvider).snapshot.data.operational!.deliveryPipeline,
    );
  }
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(timer.cancel);

  final session = ref.watch(activeSessionProvider);
  if (session == null) return {};
  try {
    return await ref
        .read(hexaApiProvider)
        .fetchDeliveryPipeline(
          businessId: session.primaryBusiness.id,
        )
        .timeout(const Duration(seconds: 15));
  } on TimeoutException {
    return {};
  }
});

/// Undelivered PUR bills across pipeline stages (same as staff home KPI).
int deliveryPipelinePendingCount(Map<String, dynamic>? pipeline) {
  if (pipeline == null || pipeline.isEmpty) return 0;
  return coerceToInt(pipeline['pending']) +
      coerceToInt(pipeline['dispatched']) +
      coerceToInt(pipeline['in_transit']) +
      coerceToInt(pipeline['arrived']) +
      coerceToInt(pipeline['staff_verifying']) +
      coerceToInt(pipeline['staff_verified']) +
      coerceToInt(pipeline['partial']);
}
