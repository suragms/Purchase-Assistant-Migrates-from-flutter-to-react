import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../shared/widgets/operational_ui.dart';

/// Dense low-stock table with status colors and reorder CTA.
class HomeLowStockSection extends ConsumerStatefulWidget {
  const HomeLowStockSection({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HomeLowStockSection> createState() => _HomeLowStockSectionState();
}

class _HomeLowStockSectionState extends ConsumerState<HomeLowStockSection> {
  bool _expanded = false;

  Color _statusColor(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('critical') || s.contains('out')) {
      return const Color(0xFFC62828);
    }
    if (s.contains('low')) return const Color(0xFFE65100);
    return const Color(0xFF2E7D32);
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(stockLowTopHomeProvider);

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => context.push('/stock/reorder'),
          child: const Text('Reorder', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () {
            ref.read(stockListQueryProvider.notifier).state =
                const StockListQuery(status: 'low', sort: 'stock_asc');
            context.go('/stock');
          },
          child: const Text('All', style: TextStyle(fontSize: 12)),
        ),
      ],
    );

    final body = rowsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load low stock',
          onRetry: () => ref.invalidate(stockLowTopHomeProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                'No low-stock items',
                style: HexaDsType.bodySm(context),
              ),
            );
          }
          final visible = _expanded ? rows : rows.take(4).toList();
          return Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  minVerticalPadding: 0,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: Text(
                    visible[i]['name']?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.listTitle(context).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${visible[i]['current_stock'] ?? '—'} / '
                    '${visible[i]['reorder_level'] ?? '—'} '
                    '${visible[i]['unit'] ?? ''}'
                    '${visible[i]['supplier_name'] != null ? ' · ${visible[i]['supplier_name']}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.bodySm(context).copyWith(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (visible[i]['stock_status'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(
                            visible[i]['stock_status']?.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Reorder',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => context.push('/stock/reorder'),
                      ),
                    ],
                  ),
                  onTap: () {
                    final id = visible[i]['id']?.toString();
                    if (id != null && id.isNotEmpty) {
                      context.push('/catalog/item/$id');
                    }
                  },
                ),
                if (i < visible.length - 1)
                  const Divider(height: 1, indent: 12, endIndent: 12),
              ],
              if (rows.length > 4)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    _expanded
                        ? 'Show less'
                        : 'Show all ${rows.length} low items',
                  ),
                ),
            ],
          );
        },
      );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body],
      );
    }

    return OperationalSection(
      title: 'Low stock',
      dense: true,
      trailing: trailing,
      child: body,
    );
  }
}
