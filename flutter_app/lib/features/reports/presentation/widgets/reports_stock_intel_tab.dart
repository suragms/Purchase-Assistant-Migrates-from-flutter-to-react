import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/operations_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import 'reports_nested_scroll.dart';
import 'slow_moving_row.dart';

/// Slow or dead stock tab inside Reports.
class ReportsStockIntelTab extends ConsumerWidget {
  const ReportsStockIntelTab({
    super.key,
    required this.dead,
  });

  final bool dead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(operationalReportsProvider);
    final key = dead ? 'dead_stock' : 'slow_moving';
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyLoadError(
        message: 'Unable to load stock intelligence',
        onRetry: () => ref.invalidate(operationalReportsProvider),
      ),
      data: (m) {
        final items = [
          for (final e in (m[key] as List? ?? []))
            if (e is Map) Map<String, dynamic>.from(e),
        ];
        if (items.isEmpty) {
          return Center(
            child: Text(
              dead
                  ? 'No dead stock items right now.'
                  : 'No slow-moving items in this snapshot.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          );
        }
        return reportsNestedListBody(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              SlowMovingRow(
                item: items[i],
                deadStyle: dead,
              ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
