import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/hexa_error_card.dart';
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
  static const LabelSize _thermalSize = LabelSize.medium;
  int _copies = 1;
  int _perRow = 2;

  /// When true, narrow the loaded "all status" list to low + critical only (client-side).
  bool _lowStockOnly = false;

  /// When true, show only catalog rows with no item_code (needs label setup).
  bool _missingCodeOnly = false;
  String _searchText = '';
  bool _busy = false;
  bool _denseA4 = true;
  String? _pdfStatus;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<BarcodeLabelData>> _fetchLabels() async {
    final session = ref.read(sessionProvider);
    if (session == null || _selected.isEmpty) return [];
    final ids = _selected.toList();
    const chunkSize = 200;
    final api = ref.read(hexaApiProvider);
    final batch = <BarcodeLabelData>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      if (!mounted) break;
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      setState(
        () => _pdfStatus =
            'Fetching labels… ${end.clamp(0, ids.length)}/${ids.length}',
      );
      final labels = await api.barcodeLabelBatch(
        businessId: session.primaryBusiness.id,
        itemIds: ids.sublist(i, end),
      );
      for (final j in labels) {
        final label = BarcodeLabelData.fromApiMap(j);
        if (label != null) batch.add(label);
      }
    }
    return batch;
  }

  Future<Uint8List?> _buildPdf() async {
    setState(() => _pdfStatus = 'Fetching labels…');
    final batch = await _fetchLabels();
    if (batch.isEmpty) {
      if (mounted) setState(() => _pdfStatus = null);
      return null;
    }
    setState(() => _pdfStatus = 'Generating PDF…');
    final session = ref.read(sessionProvider);
    final hideFinancials =
        session != null && !sessionCanSeeFinancials(session);
    try {
      if (_denseA4) {
        return BarcodePdfService.generateBatchA4Dense(
          items: batch,
          size: _thermalSize,
          copiesPerItem: _copies,
          hideFinancials: hideFinancials,
        );
      }
      return BarcodePdfService.generateBatch(
        items: batch,
        size: _thermalSize,
        copiesPerItem: _copies,
        labelsPerRow: _perRow,
        hideFinancials: hideFinancials,
      );
    } finally {
      if (mounted) setState(() => _pdfStatus = null);
    }
  }

  Future<void> _preview() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      if (!mounted) return;
      final count = _selected.length * _copies;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (ctx) => Scaffold(
            appBar: AppBar(
              title: Text('Preview ($count labels)'),
            ),
            body: PdfPreview(
              build: (_) async => pdf,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      await Printing.layoutPdf(
        name: _bulkBarcodeFilename(),
        onLayout: (_) async => pdf,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _buildPdf();
      if (pdf == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printable labels')),
        );
        return;
      }
      await Printing.sharePdf(
        bytes: pdf,
        filename: _bulkBarcodeFilename(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e)),
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
        if (_matches(it, q)) it,
    ];
  }

  bool _matches(Map<String, dynamic> it, String q) {
    final st = it['stock_status']?.toString() ?? 'healthy';
    if (_lowStockOnly && st != 'low' && st != 'critical') {
      return false;
    }
    final code = it['item_code']?.toString().trim() ?? '';
    if (_missingCodeOnly && code.isNotEmpty) {
      return false;
    }
    if (q.isEmpty) return true;
    final name = it['name']?.toString().toLowerCase() ?? '';
    final codeQ = it['item_code']?.toString().toLowerCase() ?? '';
    return name.contains(q) || codeQ.contains(q);
  }

  String _bulkBarcodeFilename() {
    final q = ref.read(stockListQueryProvider);
    final raw = q.category.trim().isNotEmpty
        ? q.category.trim()
        : (_missingCodeOnly
            ? 'missing_code'
            : (_lowStockOnly ? 'low_stock' : 'all_items'));
    final category = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'harisree_barcodes_${category.isEmpty ? 'all_items' : category}_$date.pdf';
  }

  String? _categoryIdForName(List<Map<String, dynamic>> cats, String name) {
    final t = name.trim();
    if (t.isEmpty) return null;
    for (final c in cats) {
      if ((c['name']?.toString().trim() ?? '') == t) {
        return c['id']?.toString();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final listQ = ref.watch(stockListQueryProvider);
    final listAsync = ref.watch(bulkStockListProvider);
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
              onChanged: (v) =>
                  setState(() => _searchText = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Filters', style: TextStyle(fontSize: 14)),
            initiallyExpanded: false,
            children: [
          catsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final names = [
                'All',
                for (final c in cats)
                  if ((c['name'] ?? '').toString().trim().isNotEmpty)
                    c['name'].toString().trim(),
              ];
              final cid = _categoryIdForName(cats, listQ.category);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in names)
                          FilterChip(
                            label: Text(
                              name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: name == 'All'
                                ? listQ.category.isEmpty
                                : listQ.category == name,
                            onSelected: (_) {
                              final cur = ref.read(stockListQueryProvider);
                              final n =
                                  ref.read(stockListQueryProvider.notifier);
                              if (name == 'All') {
                                n.state =
                                    cur.copyWith(category: '', subcategory: '');
                              } else {
                                n.state = cur.copyWith(
                                    category: name, subcategory: '');
                              }
                            },
                          ),
                      ],
                    ),
                    if (cid != null && cid.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ref.watch(categoryTypesListProvider(cid)).when(
                            loading: () => const LinearProgressIndicator(
                              minHeight: 2,
                            ),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (types) {
                              final typeNames = [
                                for (final t in types)
                                  if ((t['name'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    t['name'].toString().trim(),
                              ];
                              return Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  FilterChip(
                                    label: const Text(
                                      'All types',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: listQ.subcategory.isEmpty,
                                    onSelected: (_) {
                                      final cur =
                                          ref.read(stockListQueryProvider);
                                      ref
                                          .read(stockListQueryProvider.notifier)
                                          .state = cur.copyWith(subcategory: '');
                                    },
                                  ),
                                  for (final sub in typeNames)
                                    FilterChip(
                                      label: Text(
                                        sub,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      selected: listQ.subcategory == sub,
                                      onSelected: (_) {
                                        final cur =
                                            ref.read(stockListQueryProvider);
                                        ref
                                                .read(stockListQueryProvider
                                                    .notifier)
                                                .state =
                                            cur.copyWith(subcategory: sub);
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                    ],
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('All', style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'all' &&
                      !_lowStockOnly &&
                      !_missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _lowStockOnly = false;
                      _missingCodeOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label:
                      const Text('Low stock', style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'all' &&
                      _lowStockOnly &&
                      !_missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _lowStockOnly = true;
                      _missingCodeOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Missing code',
                      style: TextStyle(fontSize: 12)),
                  selected: _missingCodeOnly,
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'all');
                    setState(() {
                      _missingCodeOnly = true;
                      _lowStockOnly = false;
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Out of stock',
                      style: TextStyle(fontSize: 12)),
                  selected: listQ.status == 'out',
                  onSelected: (_) {
                    ref.read(stockListQueryProvider.notifier).state = ref
                        .read(stockListQueryProvider)
                        .copyWith(status: 'out');
                    setState(() {
                      _lowStockOnly = false;
                      _missingCodeOnly = false;
                    });
                  },
                ),
              ],
            ),
          ),
            ],
          ),
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => HexaErrorCard.fromError(
                error: e,
                title: 'Could not load items',
                onRetry: () => ref.invalidate(bulkStockListProvider),
              ),
              data: (data) {
                final raw = (data['items'] as List?) ?? const [];
                final items = [
                  for (final e in raw)
                    if (e is Map) Map<String, dynamic>.from(e),
                ];
                final visible = _filterItems(items);
                final total = (data['total'] as num?)?.toInt();
                final loaded =
                    (data['loaded'] as num?)?.toInt() ?? items.length;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selected.length} selected · '
                              '${visible.length} shown'
                              '${total != null ? ' · $loaded of $total loaded' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
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
                            subtitle: Text(
                              code.isEmpty ? 'No code · $st' : '$code · $st',
                            ),
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
                    if (_pdfStatus != null) ...[
                      LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 6),
                      Text(
                        _pdfStatus!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Thermal label (50×25 mm)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (!_denseA4) ...[
                      const SizedBox(height: 6),
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('A4 dense grid'),
                      subtitle: Text(
                        _denseA4
                            ? 'Max labels per page (5mm margin, 2mm gap)'
                            : 'Classic layout: labels per row on A4',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: _denseA4,
                      onChanged:
                          _busy ? null : (v) => setState(() => _denseA4 = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Copies per item',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        DropdownButton<int>(
                          value: _copies,
                          items: [
                            for (final n in [1, 2, 3, 4, 5])
                              DropdownMenuItem(
                                value: n,
                                child: Text('$n'),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _copies = v ?? 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                (_selected.isEmpty || _busy) ? null : _preview,
                            icon: const Icon(Icons.preview_outlined),
                            label: const Text('Preview'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_selected.isEmpty || _busy)
                                ? null
                                : _downloadPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
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
                              _busy ? '…' : 'Print',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _selected.isEmpty
                                  ? Colors.grey
                                  : HexaColors.brandPrimary,
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
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
