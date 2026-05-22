import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'offline_store.dart';

/// Replay pending stock actions queued while offline.
Future<void> replayStockOfflineQueue({
  required Ref ref,
  required String businessId,
}) async {
  final api = ref.read(hexaApiProvider);
  final pending = OfflineStore.getPendingEntries();
  for (final entry in pending) {
    final data = entry['data'];
    if (data is! Map) continue;
    if (data['businessId']?.toString() != businessId) continue;
    final id = entry['id']?.toString();
    if (id == null) continue;
    final kind = data['kind']?.toString();
    try {
      if (kind == 'stock_verify') {
        await api.verifyStockCount(
          businessId: businessId,
          itemId: data['item_id'].toString(),
          countedQty: data['counted_qty'] as num,
          reason: data['reason'].toString(),
          adjustmentType: data['adjustment_type']?.toString() ?? 'verification',
          notes: data['notes']?.toString(),
        );
      } else if (kind == 'stock_audit_line') {
        await api.upsertStockAuditLine(
          businessId: businessId,
          auditId: data['audit_id'].toString(),
          itemId: data['item_id'].toString(),
          countedQty: data['counted_qty'] as num,
          adjustmentType: data['adjustment_type']?.toString(),
          reason: data['reason']?.toString(),
          notes: data['notes']?.toString(),
        );
      } else {
        continue;
      }
      await OfflineStore.markSynced(id);
    } catch (_) {
      // Leave pending for next sync attempt.
    }
  }
}
