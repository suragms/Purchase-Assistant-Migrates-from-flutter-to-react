import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/unit_engine_summary_card.dart';
import '../../../core/widgets/warehouse_compact_card.dart';

/// Per-item warehouse detail: stock, purchases, adjustments.
class StockItemIntelligencePage extends ConsumerWidget {
  const StockItemIntelligencePage({
    super.key,
    required this.itemId,
    this.embedded = false,
    this.hideOwnerAnalytics = false,
  });

  final String itemId;
  final bool embedded;
  final bool hideOwnerAnalytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockItemIntelligenceProvider(itemId));
    final snapAsync = ref.watch(itemTodaySnapshotProvider(itemId));
    final session = ref.watch(sessionProvider);
    final staff = session != null && sessionIsStaff(session);
    final hideOwner = hideOwnerAnalytics || staff;
    final hideFinancials = session != null && !sessionCanSeeFinancials(session);
    final showOwnerBlocks = !hideOwner && !hideFinancials;

    final body = async.when(
      loading: () => const ListSkeleton(rowCount: 5, rowHeight: 72),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load item detail',
        onRetry: () => ref.invalidate(stockItemIntelligenceProvider(itemId)),
      ),
      data: (m) => _DetailBody(
        data: m,
        snapAsync: snapAsync,
        hideFinancials: hideFinancials,
        showOwnerBlocks: showOwnerBlocks,
        hideOwnerAnalytics: hideOwner,
      ),
    );

    if (embedded) {
      return ColoredBox(
        color: const Color(0xFFF5F3EE),
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item detail', style: TextStyle(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/stock/item/$itemId'),
        ),
      ),
      body: body,
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.data,
    required this.snapAsync,
    required this.hideFinancials,
    required this.showOwnerBlocks,
    required this.hideOwnerAnalytics,
  });

  final Map<String, dynamic> data;
  final AsyncValue<Map<String, dynamic>?> snapAsync;
  final bool hideFinancials;
  final bool showOwnerBlocks;
  final bool hideOwnerAnalytics;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? 'Item';
    final code = data['item_code']?.toString();
    final barcode = data['barcode']?.toString();
    final cur = coerceToDouble(data['current_stock']);
    final purchased = coerceToDouble(data['period_purchased_qty']);
    final moved = coerceToDouble(
      data['ledger_variance_qty'] ?? data['period_variance_qty'],
    );
    final reorder = coerceToDouble(data['reorder_level']);
    final unit =
        data['stock_unit']?.toString() ?? data['unit']?.toString() ?? '';
    final stockKg = coerceToDoubleNullable(data['current_stock_kg']);
    final onHandDual = dualStockDisplay(
      qty: cur,
      unit: unit.isEmpty ? 'piece' : unit,
      kgPerBag: coerceToDoubleNullable(data['default_kg_per_bag']),
      currentStockKg: stockKg,
    );
    final status = data['stock_status']?.toString() ?? '';
    final verify = data['needs_verification'] == true;
    final supplier = data['supplier_name']?.toString();
    final broker = data['broker_name']?.toString();
    final category = data['category_name']?.toString();
    final subcategory = data['subcategory_name']?.toString();
    final kgPerBag = coerceToDoubleNullable(data['default_kg_per_bag']);
    final updatedBy = data['last_stock_updated_by']?.toString();
    final updatedAt = data['last_stock_updated_at']?.toString();
    final updatedLine = [
      if (updatedBy != null && updatedBy.isNotEmpty) updatedBy,
      if (updatedAt != null && updatedAt.isNotEmpty)
        DateFormat('dd MMM, h:mm a').format(DateTime.parse(updatedAt).toLocal()),
    ].join(' • ');

    final itemMap = <String, dynamic>{
      'name': name,
      'default_unit': unit,
      'default_kg_per_bag': data['default_kg_per_bag'],
      'package_type': data['stock_tracking'] is Map
          ? (data['stock_tracking'] as Map)['mode']
          : null,
    };

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        UnitEngineSummaryCard(
          item: itemMap,
          stock: data,
          intel: data,
        ),
        const SizedBox(height: 10),
        WarehouseCompactCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE8F5E0),
                    child: Text(
                      name.isEmpty ? '?' : name.characters.first,
                      style: const TextStyle(
                        color: Color(0xFF3B6D11),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: HexaDsType.heading(16)),
                        Text(
                          [
                            if (code != null && code.isNotEmpty) 'Code $code' else 'Missing item code',
                            unit.toUpperCase(),
                            status.toUpperCase(),
                          ].join(' • '),
                          style: TextStyle(
                            fontSize: 12,
                            color: code == null || code.isEmpty
                                ? const Color(0xFFA32D2D)
                                : Colors.black54,
                            fontWeight: code == null || code.isEmpty
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Text(
                          [
                            if (category != null && category.isNotEmpty) category,
                            if (subcategory != null && subcategory.isNotEmpty) subcategory,
                            if (supplier != null && supplier.isNotEmpty) supplier,
                            if (broker != null && broker.isNotEmpty) 'Broker $broker',
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: HexaDsType.body(12),
                        ),
                        if (updatedLine.isNotEmpty)
                          Text('Last updated $updatedLine', style: HexaDsType.body(11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _metricBox(
                    'Current',
                    onHandDual.secondary == null
                        ? onHandDual.primary
                        : '${onHandDual.primary}\n${onHandDual.secondary}',
                  ),
                  _metricBox('Reorder', stockDisplayPrimary(reorder, unit)),
                  _metricBox('Bought', stockDisplayPrimary(purchased, unit)),
                  _metricBox(
                    'Variance',
                    moved.abs() > 0.0001
                        ? '${moved >= 0 ? '+' : ''}${stockDisplayPrimary(moved, unit)}'
                        : '—',
                  ),
                ],
              ),
              if (unit.toLowerCase() == 'bag' && kgPerBag != null && kgPerBag > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${kgPerBag}kg per bag conversion', style: HexaDsType.body(12)),
                ),
              if (showOwnerBlocks && data['needs_eviction'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Dead stock: review movement before reordering',
                    style: TextStyle(
                      color: Color(0xFFA32D2D),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (verify)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Needs verification',
                    style: TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!hideOwnerAnalytics)
          snapAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (snap) {
              if (snap == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: WarehouseCompactCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today snapshot', style: HexaDsType.heading(14)),
                      const SizedBox(height: 6),
                      Text('Opening: ${snap['opening_qty']}', style: HexaDsType.body(13)),
                      Text('Purchased: ${snap['purchased_qty']}', style: HexaDsType.body(13)),
                      Text('Used: ${snap['used_qty']}', style: HexaDsType.body(13)),
                      Text('Closing: ${snap['closing_qty']}', style: HexaDsType.body(13)),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        _BarcodeSection(data: data, barcode: barcode, code: code),
        const SizedBox(height: 8),
        Text('Purchase history', style: HexaDsType.heading(14)),
        const SizedBox(height: 6),
        ..._purchaseTiles(data['recent_purchases'], hideFinancials),
        const SizedBox(height: 10),
        _LedgerSection(raw: data['recent_adjustments']),
      ],
    );
  }

  Widget _metricBox(String label, String value) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0DDD8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  List<Widget> _purchaseTiles(dynamic raw, bool hideFinancials) {
    if (raw is! List || raw.isEmpty) {
      return [
        const Text('No purchases in this period', style: TextStyle(fontSize: 12)),
      ];
    }
    final df = DateFormat('dd-MMM-yyyy');
    return [
      for (final e in raw)
        if (e is Map) ...[
          Builder(builder: (context) {
            final status = _purchaseStatusLabel(e);
            final eta = e['eta']?.toString() ?? e['expected_delivery']?.toString();
            final date = e['purchase_date']?.toString();
            final dateLabel = date != null
                ? df.format(DateTime.parse(date).toLocal())
                : '';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      e['supplier_name']?.toString() ?? 'Supplier',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (status != null) _statusChip(status),
                ],
              ),
              subtitle: Text(
                [
                  '${e['qty'] ?? '—'} ${e['unit'] ?? ''}',
                  if (!hideFinancials) e['rate']?.toString(),
                  if (dateLabel.isNotEmpty) dateLabel,
                  if ((e['invoice_number']?.toString() ?? '').isNotEmpty)
                    'Invoice ${e['invoice_number']}',
                  if (eta != null && eta.isNotEmpty) 'ETA $eta',
                ].where((s) => s != null && s.toString().isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: e['id'] == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded, size: 18),
              onTap: e['id'] == null
                  ? null
                  : () => context.push('/purchase/detail/${e['id']}'),
            );
          }),
        ],
    ];
  }

  String? _purchaseStatusLabel(Map e) {
    final raw = e['delivery_status'] ??
        e['status'] ??
        e['trade_status'] ??
        e['purchase_status'];
    if (raw == null) return null;
    final s = raw.toString().toLowerCase();
    if (s.contains('pending')) return 'Pending';
    if (s.contains('arriv')) return 'Arriving';
    if (s.contains('deliver') || s.contains('received')) return 'Delivered';
    if (s.contains('delay') || s.contains('stuck')) return 'Delayed';
    return null;
  }

  Widget _statusChip(String label) {
    Color bg = const Color(0xFFE8F5E0);
    Color fg = const Color(0xFF3B6D11);
    if (label == 'Pending') {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFBA7517);
    } else if (label == 'Delayed') {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFA32D2D);
    } else if (label == 'Arriving') {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

}

class _BarcodeSection extends ConsumerStatefulWidget {
  const _BarcodeSection({
    required this.data,
    required this.barcode,
    required this.code,
  });

  final Map<String, dynamic> data;
  final String? barcode;
  final String? code;

  @override
  ConsumerState<_BarcodeSection> createState() => _BarcodeSectionState();
}

class _BarcodeSectionState extends ConsumerState<_BarcodeSection> {
  bool _saving = false;

  Future<void> _generateBarcode() async {
    if (_saving) return;
    final session = ref.read(sessionProvider);
    final id = widget.data['id']?.toString() ?? '';
    if (session == null || id.isEmpty) return;
    final seed = (widget.code ?? '').trim().isNotEmpty
        ? widget.code!.trim()
        : 'HB${id.replaceAll('-', '').substring(0, 10).toUpperCase()}';
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).patchCatalogItemBarcode(
            businessId: session.primaryBusiness.id,
            itemId: id,
            barcode: seed,
          );
      ref.invalidate(stockItemIntelligenceProvider(id));
      ref.invalidate(stockListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode $seed generated')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate barcode. Check duplicate code/barcode.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code?.trim() ?? '';
    final barcode = widget.barcode?.trim() ?? '';
    final missing = barcode.isEmpty;
    return WarehouseCompactCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Barcode', style: HexaDsType.heading(14)),
              const Spacer(),
              if (missing)
                const Text(
                  'Missing',
                  style: TextStyle(
                    color: Color(0xFFA32D2D),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 72,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: missing ? const Color(0xFFFFEBEE) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0DDD8)),
            ),
            child: missing
                ? const Text('No barcode label generated')
                : Text(
                    barcode,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (missing)
                FilledButton.icon(
                  onPressed: _saving ? null : _generateBarcode,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text(code.isEmpty ? 'Generate barcode' : 'Generate from item code'),
                ),
              OutlinedButton.icon(
                onPressed: barcode.isEmpty
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: barcode)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/barcode/print'),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('Print label'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/barcode/print'),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Download PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/barcode/print'),
                icon: const Icon(Icons.library_books_rounded, size: 18),
                label: const Text('Bulk print'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerSection extends StatefulWidget {
  const _LedgerSection({required this.raw});

  final dynamic raw;

  @override
  State<_LedgerSection> createState() => _LedgerSectionState();
}

class _LedgerSectionState extends State<_LedgerSection> {
  String _tab = 'All';
  String _period = 'Week';

  static const _tabs = ['All', 'Purchases', 'Sales', 'Usage', 'Damage', 'Corrections', 'Transfers'];
  static const _periods = ['Today', 'Week', 'Month', 'Custom'];

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return WarehouseCompactCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Item ledger', style: HexaDsType.heading(14)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _periods)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(p, style: const TextStyle(fontSize: 11)),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(t, style: const TextStyle(fontSize: 11)),
                      selected: _tab == t,
                      onSelected: (_) => setState(() => _tab = t),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text('No ledger entries for this filter', style: TextStyle(fontSize: 12))
          else
            for (final row in rows.take(8)) _ledgerTile(row),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _rows() {
    final raw = widget.raw;
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (final e in raw) {
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final type = (row['adjustment_type'] ?? '').toString().toLowerCase();
      if (!_matchesTab(type)) continue;
      final at = DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal();
      if (at != null && !_matchesPeriod(now, at)) continue;
      out.add(row);
    }
    return out;
  }

  bool _matchesTab(String type) {
    return switch (_tab) {
      'Purchases' => type == 'purchase',
      'Sales' => type == 'sale',
      'Usage' => type == 'usage' || type == 'manual',
      'Damage' => type == 'damaged' || type == 'expired',
      'Corrections' => type == 'correction' || type == 'verification',
      'Transfers' => type == 'transfer',
      _ => true,
    };
  }

  bool _matchesPeriod(DateTime now, DateTime at) {
    return switch (_period) {
      'Today' => now.year == at.year && now.month == at.month && now.day == at.day,
      'Month' => now.difference(at).inDays <= 31,
      'Custom' => true,
      _ => now.difference(at).inDays <= 7,
    };
  }

  Widget _ledgerTile(Map<String, dynamic> e) {
    final oldQty = coerceToDouble(e['old_qty']);
    final newQty = coerceToDouble(e['new_qty']);
    final delta = newQty - oldQty;
    final unit = e['unit']?.toString() ?? '';
    final at = DateTime.tryParse(e['updated_at']?.toString() ?? '')?.toLocal();
    final time = at == null ? '' : DateFormat('dd MMM, h:mm a').format(at);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${delta >= 0 ? '+' : ''}${stockDisplayPrimary(delta, unit)} • ${e['reason'] ?? e['adjustment_type'] ?? 'Stock update'}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if ((e['updated_by_name']?.toString() ?? '').isNotEmpty) e['updated_by_name'],
          if (time.isNotEmpty) time,
          '${stockDisplayPrimary(oldQty, unit)} → ${stockDisplayPrimary(newQty, unit)}',
        ].join(' • '),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
