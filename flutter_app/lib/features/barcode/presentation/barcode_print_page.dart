import 'dart:async';

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../services/barcode_pdf_service.dart';

class BarcodePrintPage extends ConsumerStatefulWidget {
  const BarcodePrintPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<BarcodePrintPage> createState() => _BarcodePrintPageState();
}

class _BarcodePrintPageState extends ConsumerState<BarcodePrintPage> {
  LabelSize _size = LabelSize.medium;
  int _copies = 1;
  bool _showLastPurchase = true;
  bool _busy = false;
  bool _loadError = false;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _loadError = false;
      _data = null;
    });
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    try {
      final j = await api.getBarcodeLabel(businessId: bid, itemId: widget.itemId);
      if (!mounted) return;
      setState(() => _data = j);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = true);
    }
  }

  BarcodeLabelData? get _label {
    final d = _data;
    if (d == null) return null;
    return BarcodeLabelData.fromApiMap(d);
  }

  Future<void> _print() async {
    final label = _label;
    if (label == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await BarcodePdfService.generateSingleLabel(
        data: label,
        size: _size,
        copies: _copies,
        showLastPurchase: _showLastPurchase,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final label = _label;
    if (label == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await BarcodePdfService.generateSingleLabel(
        data: label,
        size: _size,
        copies: _copies,
        showLastPurchase: _showLastPurchase,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'barcode_${label.itemCode}.pdf',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;

    return Scaffold(
      appBar: AppBar(
        title: Text(label != null ? label.itemName : 'Print label'),
        actions: [
          if (label != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'download') unawaited(_download());
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'download',
                  child: Text('Download PDF'),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(label),
    );
  }

  Widget _buildBody(BarcodeLabelData? label) {
    if (_loadError) {
      return FriendlyLoadError(
        message: 'Could not load label data',
        onRetry: _load,
      );
    }
    if (_data == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ListSkeleton(),
      );
    }
    if (label == null || label.itemCode.isEmpty) {
      return const Center(child: Text('No label data'));
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        Text('LABEL PREVIEW', style: HexaDsType.label(10, color: HexaDsColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                label.itemName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (label.itemCode.isNotEmpty)
                SvgPicture.string(
                  Barcode.code128().toSvg(
                    label.itemCode,
                    width: 220,
                    height: 60,
                    drawText: false,
                  ),
                  width: 220,
                  height: 60,
                ),
              const SizedBox(height: 4),
              Text(
                label.itemCode,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
              if (_size != LabelSize.small &&
                  _showLastPurchase &&
                  label.lastPurchaseDate != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Last: ${DateFormat('dd MMM yy').format(label.lastPurchaseDate!)}  '
                    '${label.lastPurchaseQty?.toStringAsFixed(0) ?? ''} '
                    '${label.lastPurchaseUnit ?? label.unit ?? ''}  '
                    '₹${label.lastPurchaseRate?.toStringAsFixed(0) ?? '—'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Label size', style: HexaDsType.label(12, color: HexaDsColors.textMuted)),
        const SizedBox(height: 8),
        SegmentedButton<LabelSize>(
          segments: const [
            ButtonSegment(value: LabelSize.small, label: Text('S')),
            ButtonSegment(value: LabelSize.medium, label: Text('M')),
            ButtonSegment(value: LabelSize.large, label: Text('L')),
          ],
          selected: {_size},
          onSelectionChanged: (s) => setState(() => _size = s.first),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Copies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_copies', style: HexaDsType.heading(18)),
              IconButton(
                onPressed: _copies < 100 ? () => setState(() => _copies++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        if (_size != LabelSize.small)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show last purchase on label'),
            subtitle: label.lastPurchaseDate != null
                ? Text(
                    '${DateFormat('dd MMM yy').format(label.lastPurchaseDate!)}  '
                    '${label.lastPurchaseQty?.toStringAsFixed(0)} '
                    '${label.lastPurchaseUnit ?? ''}',
                  )
                : const Text('No purchase data yet'),
            value: _showLastPurchase,
            onChanged: (v) => setState(() => _showLastPurchase = v),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _print,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.print_rounded),
          label: Text(_busy ? 'Preparing…' : 'Print label'),
          style: FilledButton.styleFrom(
            backgroundColor: HexaColors.brandPrimary,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }
}
