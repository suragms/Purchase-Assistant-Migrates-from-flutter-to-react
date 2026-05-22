import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/operations_providers.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../reports/presentation/widgets/slow_moving_row.dart';

enum StockOperationalListKind { dead, fast, slow }

class StockOperationalListPage extends ConsumerWidget {
  const StockOperationalListPage({super.key, required this.kind});

  final StockOperationalListKind kind;

  String get _title => switch (kind) {
        StockOperationalListKind.dead => 'Dead stock',
        StockOperationalListKind.fast => 'Fast moving',
        StockOperationalListKind.slow => 'Slow moving',
      };

  String get _key => switch (kind) {
        StockOperationalListKind.dead => 'dead_stock',
        StockOperationalListKind.fast => 'fast_moving',
        StockOperationalListKind.slow => 'slow_moving',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(operationalReportsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyLoadError(
          onRetry: () => ref.invalidate(operationalReportsProvider),
        ),
        data: (m) {
          final items = [
            for (final e in (m[_key] as List? ?? []))
              if (e is Map) Map<String, dynamic>.from(e),
          ];
          if (items.isEmpty) {
            return const Center(child: Text('No items in this list'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) => SlowMovingRow(
              item: items[i],
              deadStyle: kind == StockOperationalListKind.dead,
            ),
          );
        },
      ),
    );
  }
}
