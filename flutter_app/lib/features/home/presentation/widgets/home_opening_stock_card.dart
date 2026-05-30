import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Shown when items lack opening stock setup.
class HomeOpeningStockCard extends ConsumerWidget {
  const HomeOpeningStockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(openingStockMissingProvider).valueOrNull;
    final missing = coerceToInt(data?['missing_count']);
    if (missing <= 0) return const SizedBox.shrink();

    return Card(
      child: ListTile(
        leading: Icon(Icons.inventory_outlined, color: HexaColors.warning),
        title: Text('Set up opening stock ($missing items)'),
        subtitle: const Text('Required once per item for accurate system stock'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/stock/opening-setup'),
      ),
    );
  }
}
