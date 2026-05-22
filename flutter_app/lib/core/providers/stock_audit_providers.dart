import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final activeStockAuditProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.read(hexaApiProvider).getActiveStockAudit(
        businessId: session.primaryBusiness.id,
      );
});

final stockAuditKpisProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getStockAuditKpis(
        businessId: session.primaryBusiness.id,
      );
});
