import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/reports_bi_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';

/// Stock movement summary from adjustment logs.
class ReportsMovementTab extends ConsumerWidget {
  const ReportsMovementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportsMovementSummaryProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        message: 'Unable to load movement analytics',
        onRetry: () => ref.invalidate(reportsMovementSummaryProvider),
      ),
      data: (m) {
        final byType = m['by_type'];
        if (byType is! Map || byType.isEmpty) {
          return const Center(
            child: Text(
              'No stock movements in selected period.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          );
        }
        final chips = <Widget>[];
        byType.forEach((k, v) {
          if (v is! Map) return;
          final label = _friendlyType(k.toString());
          final delta = coerceToDouble(v['qty_delta']);
          chips.add(
            Chip(
              label: Text(
                '$label: ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          );
        });
        final timeline = m['timeline'];
        final days = timeline is List ? timeline.length : 0;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'Movement summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
            const SizedBox(height: 12),
            Text(
              '$days days with warehouse activity',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (timeline is List)
              for (final e in timeline.take(14))
                if (e is Map)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e['date']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      '${e['events'] ?? 0} events',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }

  static String _friendlyType(String t) {
    return switch (t.toLowerCase()) {
      'purchase' => 'Purchased',
      'sale' => 'Sold',
      'usage' || 'manual' => 'Usage',
      'damaged' || 'expired' => 'Damage',
      'correction' || 'verification' => 'Correction',
      'transfer' => 'Transfer',
      _ => t,
    };
  }
}
