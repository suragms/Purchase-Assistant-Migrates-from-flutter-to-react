import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../auth/provider_api_guard.dart';
import '../debug/agent_debug_log.dart';
import '../platform/app_foreground_provider.dart';
import 'stock_list_exceptions.dart';

/// Suppliers/brokers lists — wait for soft auth pause, then fetch.
Future<List<Map<String, dynamic>>> fetchContactsListWithApiGuard(
  Ref ref,
  Future<List<Map<String, dynamic>>> Function() fetch,
) async {
  // #region agent log
  agentDebugLog(
    hypothesisId: 'H3',
    location: 'contacts_list_fetch.dart:entry',
    message: 'contacts fetch start',
    data: {
      'skipApi': providerSkipApi(ref),
      'softPause': providerAuthSoftPaused(ref),
      'hardBlock': ref.read(authHardBlockApiProvider),
      'foreground': ref.read(appForegroundProvider),
    },
  );
  // #endregion
  if (!kIsWeb) {
    await awaitProviderApiReady(ref);
  }
  if (providerSkipApi(ref)) {
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H3',
      location: 'contacts_list_fetch.dart:skip',
      message: 'contacts fetch blocked by providerSkipApi',
    );
    // #endregion
    throw const StockListFetchBlockedException('api_gate');
  }
  try {
    final rows = await fetch();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H3',
      location: 'contacts_list_fetch.dart:ok',
      message: 'contacts fetch ok',
      data: {'count': rows.length},
    );
    // #endregion
    return rows;
  } catch (e, st) {
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H3',
      location: 'contacts_list_fetch.dart:error',
      message: 'contacts fetch failed',
      data: {
        'error': e.runtimeType.toString(),
        'detail': e.toString().length > 120
            ? e.toString().substring(0, 120)
            : e.toString(),
        'stackTop': st.toString().split('\n').take(2).join(' | '),
      },
    );
    // #endregion
    rethrow;
  }
}
