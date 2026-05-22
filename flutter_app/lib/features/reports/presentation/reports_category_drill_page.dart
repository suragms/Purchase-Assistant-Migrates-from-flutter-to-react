import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Category spend drill-down from Reports BI.
class ReportsCategoryDrillPage extends ConsumerWidget {
  const ReportsCategoryDrillPage({
    super.key,
    required this.categoryName,
    this.categoryId,
  });

  final String categoryName;
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          categoryName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load category detail',
          onRetry: () => ref.invalidate(analyticsCategoriesTableProvider),
        ),
        data: (rows) {
          Map<String, dynamic>? match;
          for (final r in rows) {
            final n = (r['category_name'] ?? r['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (n == categoryName.trim().toLowerCase()) {
              match = r;
              break;
            }
          }
          final amount =
              (match?['total_purchase'] ?? match?['total_amount'] ?? 0) as num;
          final qty = (match?['total_qty'] ?? match?['qty'] ?? 0) as num;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _metric('Purchase value', _inr0(amount)),
              _metric('Quantity', qty.toString()),
              if (categoryId != null && categoryId!.isNotEmpty)
                _metric('Category id', categoryId!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/reports?tab=items'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('View items in period'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/home/breakdown-more?tab=category'),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Full category list'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: HexaColors.textBody,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: HexaColors.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
