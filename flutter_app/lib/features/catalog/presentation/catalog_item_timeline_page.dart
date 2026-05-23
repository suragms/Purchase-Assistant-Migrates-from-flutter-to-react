import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/json_coerce.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../purchase/state/purchase_providers.dart';

/// Full chronological timeline for one catalog item (purchases + stock audit).
class CatalogItemTimelinePage extends ConsumerWidget {
  const CatalogItemTimelinePage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(catalogItemDetailProvider(itemId));
    final auditsAsync = ref.watch(stockItemAuditProvider(itemId));
    final historyState = ref.watch(itemHistoryLinesProvider(itemId));

    final itemName = itemAsync.valueOrNull?['name']?.toString() ?? 'Item';

    if (itemAsync.isLoading ||
        auditsAsync.isLoading ||
        historyState.loadingInitial) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.pop()),
          title: Text(
            '$itemName · Timeline',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (itemAsync.hasError ||
        auditsAsync.hasError ||
        historyState.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.pop()),
          title: const Text('Timeline'),
        ),
        body: FriendlyLoadError(
          message: historyState.errorMessage ?? 'Could not load timeline',
          onRetry: () {
            ref.invalidate(catalogItemDetailProvider(itemId));
            ref.invalidate(stockItemAuditProvider(itemId));
            ref.invalidate(itemHistoryLinesProvider(itemId));
          },
        ),
      );
    }

    final events = <_TimelineEvent>[];
    for (final row in historyState.rows) {
      events.add(_TimelineEvent(
        at: row.purchaseDate,
        kind: _TimelineKind.purchase,
        title: 'Purchased ${row.qty} ${row.unit}',
        subtitle: '${row.humanId} · ${row.supplierName}',
      ));
    }
    for (final a in auditsAsync.valueOrNull ?? const []) {
      final rawAt = a['created_at']?.toString() ??
          a['updated_at']?.toString() ??
          a['audited_at']?.toString();
      final at = DateTime.tryParse(rawAt ?? '');
      if (at == null) continue;
      final oldQ = coerceToDouble(a['old_qty']);
      final newQ = coerceToDouble(a['new_qty']);
      final diff = newQ - oldQ;
      final diffStr = (diff - diff.roundToDouble()).abs() < 0.001
          ? diff.round().toString()
          : diff.toStringAsFixed(1);
      events.add(_TimelineEvent(
        at: at,
        kind: _TimelineKind.stock,
        title: 'Stock ${diff >= 0 ? '+' : ''}$diffStr',
        subtitle: a['reason']?.toString() ??
            a['adjustment_type']?.toString() ??
            'Stock update',
      ));
    }
    events.sort((a, b) => b.at.compareTo(a.at));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Text(
          '$itemName · Timeline',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: events.isEmpty
          ? const Center(child: Text('No events recorded yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = events[i];
                final color = switch (e.kind) {
                  _TimelineKind.purchase => const Color(0xFF2E7D32),
                  _TimelineKind.stock when e.title.contains('-') =>
                    const Color(0xFFC62828),
                  _TimelineKind.stock => const Color(0xFF1565C0),
                };
                final icon = switch (e.kind) {
                  _TimelineKind.purchase => Icons.shopping_cart_rounded,
                  _TimelineKind.stock => Icons.inventory_2_rounded,
                };
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('d MMM · h:mm a').format(e.at),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (e.subtitle.isNotEmpty)
                            Text(
                              e.subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

enum _TimelineKind { purchase, stock }

class _TimelineEvent {
  const _TimelineEvent({
    required this.at,
    required this.kind,
    required this.title,
    required this.subtitle,
  });

  final DateTime at;
  final _TimelineKind kind;
  final String title;
  final String subtitle;
}
