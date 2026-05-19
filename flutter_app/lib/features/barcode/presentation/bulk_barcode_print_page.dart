import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../services/barcode_pdf_service.dart';

class BulkBarcodePrintPage extends ConsumerStatefulWidget {
  const BulkBarcodePrintPage({super.key});

  @override
  ConsumerState<BulkBarcodePrintPage> createState() =>
      _BulkBarcodePrintPageState();
}

class _BulkBarcodePrintPageState extends ConsumerState<BulkBarcodePrintPage> {
  final _selected = <String>{};
  final _searchCtrl = TextEditingController();
  LabelSize _size = LabelSize.medium;
  int _copies = 1;
  int _perRow = 2;
  String _filterCategory = '';
  String _filterStatus = 'all';
  String _searchText = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(stockListQueryProvider.notifier).state =
          ref.read(stockListQueryProvider).copyWith(perPage: 100, page: 1);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (_selected.isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(hexaApiProvider);
      final labels = await api.barcodeLabelBatch(
        businessId: session.primaryBusiness.id,
        itemIds: _selected.toList(),
      );
      final batch = <BarcodeLabelData>[];
      for (final j in labels) {
        final code = j['item_code']?.toString() ?? '';
        if (code.isEmpty) continue;
        batch.add(
          BarcodeLabelData(
            itemCode: code,
            itemName: j['item_name']?.toString() ?? code,
            unit: j['unit']?.toString(),
            currentStock: (j['current_stock'] as num?)?.toDouble(),
          ),
        );
      }
      if (batch.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      final pdf = await BarcodePdfService.generateBatch(
        items: batch,
        size: _size,
        copiesPerItem: _copies,
      );
      await Printing.layoutPdf(onLayout: (_) async => pdf);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Print failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _filterItems(List<Map<String, dynamic>> items) {
    final q = _searchText.trim().toLowerCase();
    return [
      for (final it in items)
        if (_matches(it, q))
          it,
    ];
  }

  bool _matches(Map<String, dynamic> it, String q) {
    if (_filterCategory.isNotEmpty) {
      final cat = it['category_name']?.toString() ?? '';
      if (cat != _filterCategory) return false;
    }
    final st = it['stock_status']?.toString() ?? 'healthy';
    if (_filterStatus == 'low' && st != 'low' && st != 'critical') {
      return false;
    }
    if (_filterStatus == 'out' && st != 'out') return false;
    if (q.isEmpty) return true;
    final name = it['name']?.toString().toLowerCase() ?? '';
    final code = it['item_code']?.toString().toLowerCase() ?? '';
    return name.contains(q) || code.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(stockListProvider);
    final catsAsync = ref.watch(itemCategoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? 'Bulk print barcodes'
              : 'Bulk print (${_selected.length})',
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _searchText = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 6),
          catsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final names = [
                'All',
                for (final c in cats)
                  if ((c['name'] ?? '').toString().trim().isNotEmpty)
                    c['name'].toString().trim(),
              ];
              return SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: names.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final name = names[i];
                    return FilterChip(
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      selected: name == 'All'
                          ? _filterCategory.isEmpty
                          : _filterCategory == name,
                      onSelected: (_) => setState(() {
                        _filterCategory = name == 'All' ? '' : name;
                      }),
                    );
                  },
                ),
              );
            },
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final labels = ['All', 'Low stock', 'Out of stock'];
                final values = ['all', 'low', 'out'];
                return FilterChip(
                  label: Text(labels[i], style: const TextStyle(fontSize: 12)),
                  selected: _filterStatus == values[i],
                  onSelected: (_) =>
                      setState(() => _filterStatus = values[i]),
                );
              },
            ),
          ),
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (data) {
                final raw = (data['items'] as List?) ?? const [];
                final items = [
                  for (final e in raw)
                    if (e is Map) Map<String, dynamic>.from(e),
                ];
                final visible = _filterItems(items);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            '${_selected.length} selected · ${visible.length} shown',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: visible.isEmpty
                                ? null
                                : () => setState(() {
                                    _selected
                                      ..clear()
                                      ..addAll(
                                        visible
                                            .map((e) => e['id']?.toString())
                                            .whereType<String>(),
                                      );
                                  }),
                            child: const Text('Select all'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final it = visible[i];
                          final id = it['id']?.toString() ?? '';
                          final name = it['name']?.toString() ?? '';
                          final code = it['item_code']?.toString() ?? '';
                          final st = it['stock_status']?.toString() ?? '';
                          final stock = it['current_stock']?.toString() ?? '—';
                          return CheckboxListTile(
                            dense: true,
                            value: _selected.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('$code · $st'),
                            secondary: Text(
                              stock,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: st == 'low' || st == 'critical'
                                    ? const Color(0xFFE65100)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  color: Colors.black.withValues(alpha: 0.08),
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<LabelSize>(
                            segments: const [
                              ButtonSegment(
                                value: LabelSize.small,
                                label: Text('S'),
                              ),
                              ButtonSegment(
                                value: LabelSize.medium,
                                label: Text('M'),
                              ),
                              ButtonSegment(
                                value: LabelSize.large,
                                label: Text('L'),
                              ),
                            ],
                            selected: {_size},
                            onSelectionChanged: (s) =>
                                setState(() => _size = s.first),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 2, label: Text('2/row')),
                            ButtonSegment(value: 3, label: Text('3/row')),
                          ],
                          selected: {_perRow},
                          onSelectionChanged: (s) =>
                              setState(() => _perRow = s.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          (_selected.isEmpty || _busy) ? null : _print,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print_rounded),
                      label: Text(
                        _busy
                            ? 'Generating…'
                            : 'Print ${_selected.length} labels',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _selected.isEmpty
                            ? Colors.grey
                            : HexaColors.brandPrimary,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
