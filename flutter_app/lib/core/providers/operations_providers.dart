import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart'
    show activeSessionProvider, hexaApiProvider, sessionProvider;
import '../../features/shell/shell_branch_provider.dart';
import 'home_dashboard_provider.dart' show homeChecklistFetchEnabledProvider;

bool _isAuthFailure(Object e) {
  if (e is DioException) {
    final sc = e.response?.statusCode;
    return sc == 401 || sc == 403;
  }
  return false;
}

bool _checklistSessionActive(Ref ref) {
  if (providerSkipApi(ref)) return false;
  return ref.watch(activeSessionProvider) != null;
}

final checklistTodayProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  if (!_checklistSessionActive(ref)) return {};
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      !ref.watch(homeChecklistFetchEnabledProvider)) {
    return {};
  }
  final session = ref.read(sessionProvider)!;
  try {
    final result = await ref.read(hexaApiProvider).getChecklistToday(
          businessId: session.primaryBusiness.id,
        );
    if (providerWasDisposed(disposed)) return {};
    return result;
  } catch (e) {
    if (_isAuthFailure(e)) rethrow;
    rethrow;
  }
});

final checklistTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!_checklistSessionActive(ref)) return [];
  final session = ref.read(sessionProvider)!;
  return ref.read(hexaApiProvider).getChecklistTemplates(
        businessId: session.primaryBusiness.id,
      );
});

final usageTodayProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (!_checklistSessionActive(ref)) return {};
  final session = ref.read(sessionProvider)!;
  return ref.read(hexaApiProvider).getUsageToday(
        businessId: session.primaryBusiness.id,
      );
});

final itemTodaySnapshotProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, itemId) async {
  if (!_checklistSessionActive(ref) || itemId.isEmpty) return null;
  final session = ref.read(sessionProvider)!;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final rows = await ref.read(hexaApiProvider).listDailySnapshots(
        businessId: session.primaryBusiness.id,
        fromDate: today,
        toDate: today,
        itemId: itemId,
      );
  if (rows.isEmpty) return null;
  return rows.first;
});

final operationalReportsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (!_checklistSessionActive(ref)) return {};
  final session = ref.read(sessionProvider)!;
  return ref.read(hexaApiProvider).getOperationalReports(
        businessId: session.primaryBusiness.id,
      );
});
