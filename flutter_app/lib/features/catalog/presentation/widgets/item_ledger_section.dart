import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../stock/presentation/update_stock_sheet.dart';

enum ItemLedgerRange { d7, d30, d90, all }

enum ItemLedgerKindFilter { all, purchase, physical, correction, damage, sale, transfer }

class ItemLedgerSection extends ConsumerStatefulWidget {
  const ItemLedgerSection({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemLedgerSection> createState() => _ItemLedgerSectionState();
}

class _ItemLedgerSectionState extends ConsumerState<ItemLedgerSection> {
  ItemLedgerRange _range = ItemLedgerRange.d30;
  ItemLedgerKindFilter _kind = ItemLedgerKindFilter.all;
  bool _expandedFirst = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockItemActivityProvider(widget.itemId));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Item ledger & movement', style: HexaOp.cardTitle(context)),
                ),
                TextButton(
                  onPressed: () => context.push('/catalog/item/${widget.itemId}/ledger'),
                  child: const Text('Full statement'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _filters(),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load ledger',
                onRetry: () => ref.invalidate(stockItemActivityProvider(widget.itemId)),
              ),
              data: (m) {
                final raw = (m['activity'] as List?) ?? const [];
                final unit = (m['item'] is Map)
                    ? ((m['item'] as Map)['stock_unit'] ?? (m['item'] as Map)['unit'])
                    : null;
                final unitLabel = (unit?.toString().trim().isNotEmpty == true)
                    ? unit.toString().trim().toUpperCase()
                    : '—';
                final filtered = _applyFilters(raw.whereType<Map>(), now: DateTime.now()).toList();
                if (filtered.isEmpty) {
                  return _LedgerEmptyState(
                    itemId: widget.itemId,
                    range: _range,
                    onViewAllTime: () => setState(() => _range = ItemLedgerRange.all),
                  );
                }
                final take = filtered.take(25).toList();
                return Column(
                  children: [
                    for (var i = 0; i < take.length; i++) ...[
                      _LedgerRow(
                        event: Map<String, dynamic>.from(take[i]),
                        unitLabel: unitLabel,
                        expanded: i == 0 && _expandedFirst,
                        onToggle: i == 0
                            ? () => setState(() => _expandedFirst = !_expandedFirst)
                            : null,
                      ),
                      if (i < take.length - 1)
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    ],
                    if (filtered.length > take.length) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Showing ${take.length} of ${filtered.length}. Use “Full statement” for all rows.',
                        style: HexaOp.caption(context),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    final rangeLabel = switch (_range) {
      ItemLedgerRange.d7 => '7d',
      ItemLedgerRange.d30 => '30d',
      ItemLedgerRange.d90 => '90d',
      ItemLedgerRange.all => 'All',
    };
    final kindLabel = switch (_kind) {
      ItemLedgerKindFilter.all => 'All',
      ItemLedgerKindFilter.purchase => 'Purchase',
      ItemLedgerKindFilter.physical => 'Physical',
      ItemLedgerKindFilter.correction => 'Correction',
      ItemLedgerKindFilter.damage => 'Damage',
      ItemLedgerKindFilter.sale => 'Sale',
      ItemLedgerKindFilter.transfer => 'Transfer',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _seg(
          label: 'Range: $rangeLabel',
          options: const ['7d', '30d', '90d', 'All'],
          value: rangeLabel,
          onSelect: (v) {
            setState(() {
              _range = switch (v) {
                '7d' => ItemLedgerRange.d7,
                '30d' => ItemLedgerRange.d30,
                '90d' => ItemLedgerRange.d90,
                _ => ItemLedgerRange.all,
              };
            });
          },
        ),
        _seg(
          label: 'Type: $kindLabel',
          options: const ['All', 'Purchase', 'Physical', 'Correction', 'Damage', 'Sale', 'Transfer'],
          value: kindLabel,
          onSelect: (v) {
            setState(() {
              _kind = switch (v) {
                'Purchase' => ItemLedgerKindFilter.purchase,
                'Physical' => ItemLedgerKindFilter.physical,
                'Correction' => ItemLedgerKindFilter.correction,
                'Damage' => ItemLedgerKindFilter.damage,
                'Sale' => ItemLedgerKindFilter.sale,
                'Transfer' => ItemLedgerKindFilter.transfer,
                _ => ItemLedgerKindFilter.all,
              };
            });
          },
        ),
      ],
    );
  }

  Iterable<Map> _applyFilters(
    Iterable<Map> rows, {
    required DateTime now,
  }) sync* {
    final since = switch (_range) {
      ItemLedgerRange.d7 => now.subtract(const Duration(days: 7)),
      ItemLedgerRange.d30 => now.subtract(const Duration(days: 30)),
      ItemLedgerRange.d90 => now.subtract(const Duration(days: 90)),
      ItemLedgerRange.all => null,
    };
    for (final r in rows) {
      final createdRaw = r['created_at']?.toString();
      final created = createdRaw != null ? DateTime.tryParse(createdRaw)?.toLocal() : null;
      if (since != null && created != null && created.isBefore(since)) continue;
      final kind = (r['kind'] ?? r['movement_kind'] ?? '').toString().toLowerCase();
      if (!_kindAllows(kind)) continue;
      yield r;
    }
  }

  bool _kindAllows(String kind) {
    if (_kind == ItemLedgerKindFilter.all) return true;
    if (_kind == ItemLedgerKindFilter.purchase) return kind.contains('purchase');
    if (_kind == ItemLedgerKindFilter.physical) return kind.contains('physical');
    if (_kind == ItemLedgerKindFilter.correction) return kind.contains('correction') || kind.contains('manual');
    if (_kind == ItemLedgerKindFilter.damage) return kind.contains('damage') || kind.contains('damaged') || kind.contains('expired');
    if (_kind == ItemLedgerKindFilter.sale) return kind.contains('sale') || kind.contains('usage');
    if (_kind == ItemLedgerKindFilter.transfer) return kind.contains('transfer');
    return true;
  }

  Widget _seg({
    required String label,
    required List<String> options,
    required String value,
    required ValueChanged<String> onSelect,
  }) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelect,
      itemBuilder: (ctx) => [
        for (final o in options) PopupMenuItem(value: o, child: Text(o)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _LedgerEmptyState extends ConsumerWidget {
  const _LedgerEmptyState({
    required this.itemId,
    required this.range,
    required this.onViewAllTime,
  });

  final String itemId;
  final ItemLedgerRange range;
  final VoidCallback onViewAllTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (range == ItemLedgerRange.all) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Text(
          'No ledger entries in this range.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      );
    }

    final detail = ref.watch(stockItemDetailProvider(itemId)).valueOrNull;
    final systemStock = coerceToDouble(detail?['current_stock']);
    final itemName = detail?['name']?.toString() ?? 'Item';

    if (systemStock <= 0.001) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Text(
          'No ledger entries in this range.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'System stock is positive but nothing moved in this range. '
            'Try a wider range or update the physical count.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onViewAllTime,
                child: const Text('View all time'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final row =
                      detail ?? await ref.read(stockItemDetailProvider(itemId).future);
                  if (!context.mounted) return;
                  await showUpdateStockSheet(
                    context: context,
                    ref: ref,
                    itemId: itemId,
                    itemName: itemName,
                    stockRow: row == null || row.isEmpty ? null : row,
                  );
                },
                child: const Text('Update physical count'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.event,
    required this.unitLabel,
    required this.expanded,
    required this.onToggle,
  });

  final Map<String, dynamic> event;
  final String unitLabel;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final kind = (event['kind'] ?? '').toString();
    final title = (event['title'] ?? kind).toString();
    final actor = (event['actor_name'] ?? '').toString().trim();
    final atRaw = event['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw)?.toLocal() : null;
    final delta = coerceToDouble(event['delta_qty']);
    final before = event['qty_before'];
    final after = event['qty_after'];
    final beforeLabel = before == null ? '—' : formatStockQtyNumber(coerceToDouble(before));
    final afterLabel = after == null ? '—' : formatStockQtyNumber(coerceToDouble(after));
    final deltaLabel = delta == 0 ? '—' : '${delta > 0 ? '+' : ''}${formatStockQtyNumber(delta)} $unitLabel';

    final sourceType = event['source_type']?.toString();
    final sourceId = event['source_id']?.toString();
    final supplier = event['supplier_name']?.toString();
    final broker = event['broker_name']?.toString();
    final notes = (event['notes'] ?? '').toString().trim();

    final isDanger = kind.contains('damage') || kind.contains('correction') || kind.contains('physical');
    final accent = isDanger ? const Color(0xFFA32D2D) : HexaColors.brandPrimary;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
                Text(
                  deltaLabel,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: accent),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (at != null) DateFormat('dd MMM yyyy • h:mm a').format(at),
                if (actor.isNotEmpty) actor,
                '$beforeLabel → $afterLabel',
              ].join('  ·  '),
              maxLines: expanded ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              if ((supplier ?? '').trim().isNotEmpty || (broker ?? '').trim().isNotEmpty)
                Text(
                  [
                    if ((supplier ?? '').trim().isNotEmpty) 'Supplier: ${supplier!.trim()}',
                    if ((broker ?? '').trim().isNotEmpty) 'Broker: ${broker!.trim()}',
                  ].join('  •  '),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              if (notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(notes, style: const TextStyle(fontSize: 11)),
                ),
              if (sourceType == 'trade_purchase' && sourceId != null && sourceId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/purchase/detail/$sourceId'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open purchase'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

