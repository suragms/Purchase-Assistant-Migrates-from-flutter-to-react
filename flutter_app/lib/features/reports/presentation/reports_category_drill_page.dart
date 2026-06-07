import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'reports_drill_format.dart';

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
    final itemsAsync = ref.watch(analyticsItemsTableProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          categoryName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          final dio = e is DioException ? e : null;
          final offline = dio != null && dioIsNetworkError(dio);
          return FriendlyLoadError(
            message: offline
                ? 'Could not load category detail — check connection'
                : 'Could not load category detail. Server error — tap to retry.',
            onRetry: () => ref.invalidate(analyticsCategoriesTableProvider),
          );
        },
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
          final unit = match?['unit']?.toString();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                categoryName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _metric('Purchase value', _inr0(amount)),
              _metric(
                'Quantity',
                reportsQtyWithUnit(qty, unit),
                valueBold: true,
              ),
              if (categoryId != null && categoryId!.isNotEmpty)
                _metric('Category id', categoryId!),
              const SizedBox(height: 16),
              itemsAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => FriendlyLoadError(
                  message: 'Could not load items for this category.',
                  onRetry: () => ref.invalidate(analyticsItemsTableProvider),
                ),
                data: (items) {
                  final filtered = reportsItemsForCategory(items, categoryName);
                  final list = filtered.isNotEmpty
                      ? filtered
                      : (List<Map<String, dynamic>>.from(items)
                        ..sort(
                          (a, b) => coerceToDouble(b['total_purchase'])
                              .compareTo(coerceToDouble(a['total_purchase'])),
                        ));
                  final top = list.take(20).toList();
                  if (top.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ITEMS IN PERIOD',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: HexaColors.textBody.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...top.map(
                        (r) => ReportsDrillItemTile(
                          itemName: (r['item_name'] ?? 'Item').toString(),
                          qtyLine: reportsItemQtyLine(r),
                          supplierName: r['supplier_name']?.toString(),
                          amountLine: reportsInr0(
                            coerceToDouble(r['total_purchase']),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
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

  Widget _metric(String label, String value, {bool valueBold = false}) {
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
            style: TextStyle(
              fontWeight: valueBold ? FontWeight.w900 : FontWeight.w800,
              color: HexaColors.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
