import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../stock/presentation/widgets/stock_qty_metric_column.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../stock/presentation/widgets/operational_stock_filter_sheet.dart';
import '../../../core/providers/api_degraded_provider.dart';
import '../services/barcode_pdf_service.dart';
import '../services/bulk_label_batch.dart';
import '../services/bulk_label_from_stock.dart';
import '../services/bulk_pdf_chunks.dart';
import 'bulk_barcode_print_controller.dart';
import 'bulk_barcode_print_preview_panel.dart';
import 'bulk_barcode_print_toolbar.dart';

class BulkBarcodePrintPage extends ConsumerStatefulWidget {
  const BulkBarcodePrintPage({super.key});

  @override
  ConsumerState<BulkBarcodePrintPage> createState() =>
      _BulkBarcodePrintPageState();
}

class _BulkBarcodePrintPageState extends ConsumerState<BulkBarcodePrintPage> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  static const LabelSize _thermalSize = LabelSize.medium;
  int _copies = 1;
  final int _perRow = 2;
  bool _busy = false;
  bool _denseA4 = true;
  bool _useQr = true;
  BulkLabelsPerPdfFile _labelsPerPdfFile = BulkLabelsPerPdfFile.n50;
  String? _pdfStatus;
  int _labelProgressDone = 0;
  int _labelProgressTotal = 0;
  Future<void> Function()? _lastPdfRetry;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(stockListQueryProvider).q;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Set<String> get _selected => ref.read(bulkBarcodeSelectionProvider);

  void _setSelected(Set<String> next) {
    ref.read(bulkBarcodeSelectionProvider.notifier).state = next;
  }

  void _toggleSelected(String id, bool on) {
    final next = Set<String>.from(_selected);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _setSelected(next);
  }

  Map<String, Map<String, dynamic>> _stockRowsById() {
    final data = ref.read(bulkStockListProvider).valueOrNull;
    final items = data?['items'];
    if (items is! List) return const {};
    return stockRowsByIdFromList([
      for (final e in items)
        if (e is Map) Map<String, dynamic>.from(e),
    ]);
  }

  Future<BulkLabelBatchResult> _loadLabels({List<String>? ids}) async {
    final target = ids ?? ref.read(bulkBarcodeSelectionProvider).toList();
    if (mounted) {
      setState(() {
        _labelProgressTotal = target.length;
        _labelProgressDone = 0;
      });
    }
    final batch = await fetchBulkLabels(
      ref: ref,
      ids: target,
      stockById: _stockRowsById(),
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _labelProgressDone = done;
          _labelProgressTotal = total;
          _pdfStatus = 'Preparing labels… $done / $total';
        });
      },
    );
    return batch;
  }

  static const int _kMaxLabelsPerPdf = 100;

  Future<void> _runPdfFlow({
    required Future<void> Function(List<Uint8List> pdfs) action,
    required Future<void> Function() retry,
  }) async {
    if (_selected.isEmpty || _busy) return;
    _lastPdfRetry = retry;
    setState(() => _busy = true);
    try {
      var targetIds = ref.read(bulkBarcodeSelectionProvider).toList();
      if (targetIds.length > _kMaxLabelsPerPdf) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Select at most $_kMaxLabelsPerPdf labels per PDF. '
              'You have ${targetIds.length} selected.',
            ),
            action: SnackBarAction(
              label: 'Use first $_kMaxLabelsPerPdf',
              onPressed: () {
                _setSelected(targetIds.take(_kMaxLabelsPerPdf).toSet());
              },
            ),
          ),
        );
        return;
      }
      final batch = await _loadLabels(ids: targetIds);
      if (batch.labels.isEmpty) {
        if (!mounted) return;
        _showError(
          batch.isTotalFailure
              ? (batch.failuresById.values.isNotEmpty
                  ? batch.failuresById.values.first
                  : 'Could not load labels. Sign in, check network, or pick items with barcodes.')
              : 'No printable labels in selection.',
        );
        return;
      }
      if (batch.isTotalFailure) {
        if (!mounted) return;
        final hint = batch.failuresById.values.isNotEmpty
            ? batch.failuresById.values.first
            : 'Check barcodes and try again.';
        _showError(
          '${batch.failedIds.length} items could not be loaded. $hint',
        );
        return;
      }
      if (batch.hasPartialFailure) {
        final cont = await showPartialLabelFailureDialog(context, batch);
        if (cont != true) return;
      }
      setState(() => _pdfStatus = 'Generating PDF…');
      final symbol = bulkPrintSymbolMode(denseA4: _denseA4, useQr: _useQr);
      final pdfs = await generateBulkPdfParts(
        context: context,
        ref: ref,
        batch: batch,
        denseA4: _denseA4,
        copies: _copies,
        perRow: _perRow,
        symbol: symbol,
        thermalSize: _thermalSize,
        labelsPerFile: _labelsPerPdfFile.count,
      );
      await action(pdfs);
      if (!mounted) return;
      final perFile = _labelsPerPdfFile.count;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _denseA4
                ? (pdfs.length == 1
                    ? 'One A4 PDF ready — up to $perFile labels per page. Print once and cut.'
                    : '${pdfs.length} PDFs ready.')
                : (pdfs.length == 1
                    ? 'PDF ready (up to $perFile labels per file).'
                    : '${pdfs.length} PDFs ready (up to $perFile labels each).'),
          ),
        ),
      );
    } on BarcodeOperationException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return;
      _showError(barcodeMessageForUser(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pdfStatus = null;
          _labelProgressDone = 0;
          _labelProgressTotal = 0;
        });
      }
    }
  }

  void _showError(String message) {
    final retry = _lastPdfRetry;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: retry == null ? () {} : () => unawaited(retry()),
        ),
      ),
    );
  }

  String _bulkBarcodeFilename({int? part, int? partCount}) {
    final q = ref.read(stockListQueryProvider);
    final raw = q.category.trim().isNotEmpty ? q.category.trim() : 'all_items';
    final category = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    final base =
        'harisree_barcodes_${category.isEmpty ? 'all_items' : category}_$date';
    if (part != null && partCount != null && partCount > 1) {
      return '${base}_part${part}_of_$partCount.pdf';
    }
    return '$base.pdf';
  }

  Future<void> _openPdfPage(
    Uint8List pdf, {
    required String title,
    String? filename,
  }) async {
    if (!mounted) return;
    final name = filename ?? _bulkBarcodeFilename();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              TextButton.icon(
                onPressed: () => unawaited(
                  Printing.sharePdf(
                    bytes: pdf,
                    filename: name,
                  ),
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download PDF'),
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) async => pdf,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            actions: const [],
          ),
        ),
      ),
    );
  }

  Future<void> _preview() => _runPdfFlow(
        retry: _preview,
        action: (pdfs) async {
          if (!mounted || pdfs.isEmpty) return;
          final total = _selected.length * _copies;
          await _openPdfPage(
            pdfs.first,
            title: pdfs.length == 1
                ? 'Preview ($total labels)'
                : 'Preview part 1 of ${pdfs.length}',
            filename: _bulkBarcodeFilename(part: 1, partCount: pdfs.length),
          );
        },
      );

  Future<void> _downloadPdf() => _runPdfFlow(
        retry: _downloadPdf,
        action: (pdfs) async {
          if (!mounted) return;
          final n = pdfs.length;
          for (var i = 0; i < n; i++) {
            final name = _bulkBarcodeFilename(part: i + 1, partCount: n);
            if (kIsWeb && i == 0) {
              await _openPdfPage(
                pdfs[i],
                title: n == 1
                    ? 'Download labels (${_selected.length})'
                    : 'Download part 1 of $n',
                filename: name,
              );
            } else {
              await Printing.sharePdf(bytes: pdfs[i], filename: name);
            }
          }
          if (kIsWeb && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  n == 1
                      ? 'Use Download PDF in the app bar, or the share sheet below the preview.'
                      : 'Downloaded $n PDF files (check your downloads folder).',
                ),
              ),
            );
          }
        },
      );

  Future<void> _print() => _runPdfFlow(
        retry: _print,
        action: (pdfs) async {
          if (!mounted) return;
          final n = pdfs.length;
          for (var i = 0; i < n; i++) {
            final name = _bulkBarcodeFilename(part: i + 1, partCount: n);
            if (kIsWeb) {
              await Printing.sharePdf(bytes: pdfs[i], filename: name);
            } else {
              await guardWebPrint(
                () => Printing.layoutPdf(
                  name: name,
                  onLayout: (_) async => pdfs[i],
                ),
              );
            }
          }
          if (kIsWeb && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  n == 1
                      ? 'On web, use the downloaded PDF to print from your browser.'
                      : 'Shared $n PDFs — print each from your browser.',
                ),
              ),
            );
          }
        },
      );

  List<Map<String, dynamic>> _applyClientFilters(List<Map<String, dynamic>> items) {
    final op = ref.read(stockOperationalFiltersProvider);
    return [
      for (final it in items)
        if (_passesOperational(it, op)) it,
    ];
  }

  bool _passesOperational(Map<String, dynamic> it, StockOperationalFilters op) {
    if (op.missingBarcodeOnly && it['missing_barcode'] != true) return false;
    if (op.missingItemCodeOnly && it['missing_item_code'] != true) return false;
    if (op.reorderOnly) {
      final reorder = double.tryParse('${it['reorder_level']}') ?? 0;
      final current = double.tryParse('${it['current_stock']}') ?? 0;
      if (reorder <= 0 || current > reorder) return false;
    }
    if (op.unit.isNotEmpty) {
      final u = (it['unit']?.toString() ?? '').toLowerCase();
      if (u != op.unit) return false;
    }
    if (op.purchasedInPeriodOnly) {
      final p = double.tryParse('${it['period_purchased_qty']}') ?? 0;
      if (p <= 0) return false;
    }
    return true;
  }

  Widget _searchRow() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final filterCount = countOperationalActiveFilters(q, op);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HexaOp.pageGutter,
        8,
        HexaOp.pageGutter,
        4,
      ),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search name, code, barcode, category…',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: IconButton(
            tooltip: 'Filters',
            onPressed: () => showOperationalStockFilter(context: context, ref: ref),
            icon: Badge(
              isLabelVisible: filterCount > 0,
              label: Text('$filterCount'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
        ),
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            ref.read(stockListQueryProvider.notifier).state =
                ref.read(stockListQueryProvider).copyWith(q: v.trim(), page: 1);
          });
        },
      ),
    );
  }

  Widget _filterSummaryChip() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    final summary = stockActiveFilterSummary(q, op);
    if (summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          label: Text('Filters: $summary', style: const TextStyle(fontSize: 11)),
          onPressed: () => showOperationalStockFilter(context: context, ref: ref),
        ),
      ),
    );
  }

  Widget _quickFilterChips() {
    final q = ref.watch(stockListQueryProvider);
    final op = ref.watch(stockOperationalFiltersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 2, HexaOp.pageGutter, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          FilterChip(
            label: const Text('Missing code', style: TextStyle(fontSize: 11)),
            selected: op.missingItemCodeOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                missingItemCodeOnly: !op.missingItemCodeOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Missing barcode', style: TextStyle(fontSize: 11)),
            selected: op.missingBarcodeOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                missingBarcodeOnly: !op.missingBarcodeOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Low stock', style: TextStyle(fontSize: 11)),
            selected: q.status == 'low',
            onSelected: (_) {
              ref.read(stockListQueryProvider.notifier).state = q.copyWith(
                status: q.status == 'low' ? 'all' : 'low',
                page: 1,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          FilterChip(
            label: const Text('Reorder', style: TextStyle(fontSize: 11)),
            selected: op.reorderOnly,
            onSelected: (_) {
              ref.read(stockOperationalFiltersProvider.notifier).state = op.copyWith(
                reorderOnly: !op.reorderOnly,
              );
            },
            visualDensity: VisualDensity.compact,
          ),
          ActionChip(
            label: const Text('Category/Supplier', style: TextStyle(fontSize: 11)),
            onPressed: () => showOperationalStockFilter(context: context, ref: ref),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(bulkBarcodeSelectionProvider);
    final listAsync = ref.watch(bulkStockListProvider);
    final progress = _labelProgressTotal > 0
        ? _labelProgressDone / _labelProgressTotal
        : null;

    final sessionHint = ref.watch(apiDegradedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk print'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => _setSelected({}),
              child: const Text('Clear'),
            ),
        ],
      ),
      bottomNavigationBar: BulkBarcodePrintToolbar(
        selectedCount: selected.length,
        busy: _busy,
        denseA4: _denseA4,
        useQr: _useQr,
        copies: _copies,
        labelsPerPdfFile: _labelsPerPdfFile,
        progress: progress,
        statusText: _pdfStatus,
        onDenseA4Changed: (v) => setState(() {
          _denseA4 = v;
          if (v && _labelsPerPdfFile == BulkLabelsPerPdfFile.n30) {
            _labelsPerPdfFile = BulkLabelsPerPdfFile.n50;
          }
        }),
        onQrChanged: (v) => setState(() => _useQr = v),
        onCopiesChanged: (v) => setState(() => _copies = v),
        onLabelsPerPdfFileChanged: (v) => setState(() => _labelsPerPdfFile = v),
        onPreview: _preview,
        onPdf: _downloadPdf,
        onPrint: _print,
        pdfButtonLabel: kIsWeb ? 'Download' : 'PDF',
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= kOperationalDesktopBreakpoint;
          final listPane = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessionHint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HexaOp.pageGutter,
                    8,
                    HexaOp.pageGutter,
                    0,
                  ),
                  child: Material(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: Color(0xFFC62828),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sessionHint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_denseA4)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HexaOp.pageGutter,
                    6,
                    HexaOp.pageGutter,
                    0,
                  ),
                  child: Text(
                    'Tip: choose A4 + 50/pg for one sheet with many labels to cut.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              _searchRow(),
              _quickFilterChips(),
              _filterSummaryChip(),
              Expanded(
                child: listAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => HexaErrorCard.fromError(
                    error: e,
                    title: 'Could not load items',
                    onRetry: () => ref.invalidate(bulkStockListProvider),
                  ),
                  data: (data) => _buildList(data, selected, desktop),
                ),
              ),
            ],
          );

          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: listPane),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: BulkBarcodePrintPreviewPanel(
                    denseA4: _denseA4,
                    useQr: _useQr,
                    copies: _copies,
                    selectedCount: selected.length,
                    onPreviewAll: () => unawaited(_preview()),
                  ),
                ),
              ],
            );
          }
          return listPane;
        },
      ),
    );
  }

  Widget _buildList(
    Map<String, dynamic> data,
    Set<String> selected,
    bool desktop,
  ) {
    final raw = (data['items'] as List?) ?? const [];
    final items = [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final visible = _applyClientFilters(items);
    final total = data['total'];
    final loaded = items.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HexaOp.pageGutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} shown · $loaded loaded'
                  '${total != null ? ' · $total total' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: visible.isEmpty
                    ? null
                    : () {
                        final ids = <String>{
                          for (final e in visible.take(_kMaxLabelsPerPdf))
                            if (e['id'] != null) e['id'].toString(),
                        };
                        _setSelected(ids);
                        if (visible.length > _kMaxLabelsPerPdf && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Selected first $_kMaxLabelsPerPdf of '
                                '${visible.length} items (batch limit).',
                              ),
                            ),
                          );
                        }
                      },
                child: Text(
                  visible.length > _kMaxLabelsPerPdf
                      ? 'Select $_kMaxLabelsPerPdf'
                      : 'Select all',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(HexaOp.pageGutter, 0, 56, 2),
          child: Row(
            children: const [
              Expanded(child: SizedBox()),
              SizedBox(
                width: 40,
                child: Text(
                  'Buy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black38,
                  ),
                ),
              ),
              SizedBox(width: 2),
              SizedBox(
                width: 40,
                child: Text(
                  'Now',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black38,
                  ),
                ),
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
              final barcode = it['barcode']?.toString() ?? '';
              final st = it['stock_status']?.toString() ?? '';
              final cur = coerceToDouble(it['current_stock']);
              final purchased = coerceToDouble(
                it['period_purchased_qty'] ?? it['purchased_today_qty'],
              );
              final sub = barcode.isEmpty
                  ? (code.isEmpty ? 'No barcode · $st' : '$code · $st')
                  : (code.isEmpty ? '$barcode · $st' : '$code · $barcode · $st');
              return _BulkPrintRow(
                selected: selected.contains(id),
                name: name,
                subtitle: sub,
                purchased: purchased,
                current: cur,
                stockHighlight: st == 'low' || st == 'critical' || st == 'out',
                onChanged: (v) => _toggleSelected(id, v),
                onPreview: id.isEmpty
                    ? null
                    : () {
                        ref.read(bulkPreviewItemIdProvider.notifier).state = id;
                        if (!desktop) {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (sheetCtx) => Padding(
                              padding: EdgeInsets.only(
                                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
                              ),
                              child: SingleChildScrollView(
                                child: SizedBox(
                              height: 280,
                              child: BulkBarcodePrintPreviewPanel(
                                denseA4: _denseA4,
                                useQr: _useQr,
                                copies: _copies,
                                selectedCount: selected.length,
                                onPreviewAll: () {
                                  Navigator.pop(context);
                                  unawaited(_preview());
                                },
                              ),
                            ),
                              ),
                            ),
                          );
                        }
                      },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BulkPrintRow extends StatelessWidget {
  const _BulkPrintRow({
    required this.selected,
    required this.name,
    required this.subtitle,
    required this.purchased,
    required this.current,
    required this.stockHighlight,
    required this.onChanged,
    this.onPreview,
  });

  final bool selected;
  final String name;
  final String subtitle;
  final double purchased;
  final double current;
  final bool stockHighlight;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HexaOp.listRowMax,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (onPreview != null)
                  IconButton(
                    tooltip: 'Preview label',
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    onPressed: onPreview,
                  ),
                StockQtyMetricTriple(
                  purchased: purchased,
                  current: current,
                  moved: 0,
                  highlightCurrent: stockHighlight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
