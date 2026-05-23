import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/router/navigation_ext.dart';

/// Client-side reorder urgency from stock + recent purchase velocity.
class ReorderSuggestionsPage extends ConsumerWidget {
  const ReorderSuggestionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text(
          'Smart Reorder',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(stockListProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (payload) {
          final items = (payload['items'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          final suggestions = <({Map<String, dynamic> item, double days})>[];
          for (final item in items) {
            final stock = coerceToDouble(item['current_stock']);
            final purchased30 =
                coerceToDouble(item['period_purchased_qty'] ?? item['purchased_qty_period']);
            final daily = purchased30 > 0 ? purchased30 / 30 : 0.0;
            if (daily <= 0 || stock <= 0) continue;
            final days = stock / daily;
            if (days <= 7) {
              suggestions.add((item: item, days: days));
            }
          }
          suggestions.sort((a, b) => a.days.compareTo(b.days));
          if (suggestions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No items predicted to run out in the next 7 days',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = suggestions[i];
              final item = s.item;
              final id = item['id']?.toString() ?? '';
              final name = item['name']?.toString() ?? 'Item';
              final unit = item['default_unit']?.toString() ?? '';
              final critical = s.days < 3;
              return Card(
                child: ListTile(
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '~${s.days.ceil()} days remaining · Current: ${stockDisplay(coerceToDouble(item['current_stock']), unit)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: critical
                          ? const Color(0xFFC62828)
                          : const Color(0xFFEF6C00),
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: id.isEmpty
                        ? null
                        : () => context.push('/purchase/new?prefill=$id'),
                    child: const Text('Order', style: TextStyle(fontSize: 11)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String stockDisplay(double qty, String unit) {
    final r = qty.roundToDouble();
    final q = (qty - r).abs() < 0.001 ? r.round().toString() : qty.toStringAsFixed(1);
    return '$q $unit'.trim();
  }
}
