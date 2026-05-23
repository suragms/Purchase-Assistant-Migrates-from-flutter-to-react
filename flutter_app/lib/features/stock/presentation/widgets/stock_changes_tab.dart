import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/hexa_error_card.dart';
import '../quick_stock_patch_sheet.dart';

/// **Changes** tab: recent stock audit events for [stockPagePeriodProvider].
class StockChangesTab extends ConsumerWidget {
  const StockChangesTab({
    super.key,
    this.isStaffMode = false,
  });

  final bool isStaffMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(stockPagePeriodProvider);
    final feed = ref.watch(stockChangesFeedProvider);

    return feed.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => HexaErrorCard.fromError(
        error: e,
        title: 'Could not load stock changes',
        onRetry: () => ref.invalidate(stockChangesFeedProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No stock changes for ${period.label.toLowerCase()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(stockChangesFeedProvider);
            await ref.read(stockChangesFeedProvider.future);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              8,
              HexaOp.pageGutter,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final name = r['item_name']?.toString() ??
                  r['catalog_item_name']?.toString() ??
                  'Item';
              final delta = coerceToDouble(r['qty_delta'] ?? r['delta']);
              final reason = r['reason']?.toString() ??
                  r['adjustment_type']?.toString() ??
                  'Update';
              final at = DateTime.tryParse(
                    r['created_at']?.toString() ??
                        r['audited_at']?.toString() ??
                        '',
                  ) ??
                  DateTime.now();
              final by = r['user_name']?.toString() ??
                  r['updated_by']?.toString() ??
                  '';
              final itemId = r['item_id']?.toString() ??
                  r['catalog_item_id']?.toString();
              final sign = delta >= 0 ? '+' : '';
              final color = delta >= 0
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFC62828);

              return Material(
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(
                      delta >= 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '$reason · ${DateFormat.jm().format(at)}'
                    '${by.isNotEmpty ? ' · $by' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    '$sign${delta == delta.roundToDouble() ? delta.round() : delta.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  onTap: itemId == null || itemId.isEmpty
                      ? null
                      : () async {
                          if (isStaffMode) {
                            final stock = await ref.read(
                              stockItemDetailProvider(itemId).future,
                            );
                            if (!context.mounted) return;
                            if (stock.isEmpty) {
                              context.push('/catalog/item/$itemId');
                              return;
                            }
                            await showQuickStockPatchSheet(
                              context: context,
                              ref: ref,
                              item: stock,
                            );
                          } else {
                            context.push('/catalog/item/$itemId');
                          }
                        },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
