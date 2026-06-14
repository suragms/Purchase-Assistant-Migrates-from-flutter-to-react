import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import 'stock_list_exceptions.dart';

/// Suppliers/brokers lists — wait for soft auth pause, then fetch.
Future<List<Map<String, dynamic>>> fetchContactsListWithApiGuard(
  Ref ref,
  Future<List<Map<String, dynamic>>> Function() fetch,
) async {
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    throw const StockListFetchBlockedException('api_gate');
  }
  return fetch();
}
