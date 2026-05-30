import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/widgets/section_inline_error.dart';
import '../../../../shared/widgets/operational_ui.dart';

/// Dense low-stock table with status colors and reorder CTA.
class HomeLowStockSection extends ConsumerStatefulWidget {
  const HomeLowStockSection({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<HomeLowStockSection> createState() => _HomeLowStockSectionState();
}

class _HomeLowStockSectionState extends ConsumerState<HomeLowStockSection> {
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
          onPressed: () => context.push('/stock/low-stock'),
          child: const Text('All', style: TextStyle(fontSize: 12)),
        ),
      ],
    );

    final body = rowsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => SectionInlineError(
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
          final visible = rows.take(5).toList();
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
                    [
                      if ((visible[i]['subcategory_name']?.toString().trim() ?? '')
                          .isNotEmpty)
                        visible[i]['subcategory_name']?.toString(),
                      '${visible[i]['current_stock'] ?? '—'} / '
                          '${visible[i]['reorder_level'] ?? '—'} '
                          '${visible[i]['unit'] ?? ''}',
                      if (visible[i]['supplier_name'] != null)
                        visible[i]['supplier_name']?.toString(),
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
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
                      Tooltip(
                        message: 'Reorder',
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text(
                            'Order',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          onPressed: () => context.push('/stock/reorder'),
                        ),
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
              if (rows.length > 5)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push('/stock/low-stock'),
                    child: Text(
                      'View all ${rows.length} low stock items',
                      style: const TextStyle(fontSize: 12),
                    ),
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
      onTitleTap: () => context.push('/stock/low-stock'),
      child: body,
    );
  }
}
