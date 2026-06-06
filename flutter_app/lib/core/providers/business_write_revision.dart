import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monotonic counter bumped after any business write that affects purchases,
/// ledgers, or catalog-derived metrics. Screens with sliced or family-scoped
/// data listen and refetch / invalidate their own providers.
final businessDataWriteRevisionProvider = StateProvider<int>((ref) => 0);

/// Bumped when `/realtime-events` reports remote changes (other users/devices).
final remoteBusinessDataRevisionProvider = StateProvider<int>((ref) => 0);

void bumpBusinessDataWriteRevision(dynamic ref) {
  ref.read(businessDataWriteRevisionProvider.notifier).state++;
}

void bumpRemoteBusinessDataRevision(dynamic ref) {
  ref.read(remoteBusinessDataRevisionProvider.notifier).state++;
}
