import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/brokers_list_provider.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../core/search/catalog_fuzzy.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../domain/purchase_draft.dart';
import 'scan_review_shared.dart';

/// Bill scan + editable preview → [onApplyDraft] merges into wizard (no standalone route).
class PurchaseBillScanPanel extends ConsumerStatefulWidget {
  const PurchaseBillScanPanel({
    super.key,
    required this.onApplyDraft,
    this.compactHeading = false,
    this.applyButtonLabel = 'Apply to purchase',
    this.applyButtonIcon = Icons.check_rounded,
  });

  final void Function(PurchaseDraft draft) onApplyDraft;

  /// Hides redundant intro paragraph when embedded in wizard.
  final bool compactHeading;

  /// Standalone scan route vs embedded wizard wording.
  final String applyButtonLabel;
  final IconData applyButtonIcon;

  @override
  ConsumerState<PurchaseBillScanPanel> createState() =>
      _PurchaseBillScanPanelState();
}

class _PurchaseBillScanPanelState extends ConsumerState<PurchaseBillScanPanel> {
  bool _busy = false;
  String? _note;
  bool _userConfirmedPreview = false;
  double? _legacyScanConfidence;
  bool _legacyHasTotalMismatch = false;
  List<String> _legacyParseWarnings = [];

  /// Server keys for red borders after scan.
  final Set<String> _missing = {};
  List<_BillRowEdit> _rows = [];
  List<int>? _jpegBytes;

  final _supplierCtrl = TextEditingController();
  String? _supplierDirectoryId;
  Map<String, dynamic>? _supplierFuzzySuggestion;

  final _brokerCtrl = TextEditingController();
  String? _brokerDirectoryId;
  Map<String, dynamic>? _brokerFuzzySuggestion;
  final _deliveredCtrl = TextEditingController();
  final _billtyCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  String _freightType = 'separate';

  void _refreshSupplierDirectoryLink() {
    final q = _supplierCtrl.text.trim();
    if (q.isEmpty) {
      _supplierDirectoryId = null;
      _supplierFuzzySuggestion = null;
      return;
    }
    final suppliers = ref.read(suppliersListProvider).valueOrNull ?? [];
    for (final m in suppliers) {
      final n = m['name']?.toString().trim() ?? '';
      if (n.isEmpty) continue;
      if (normalizeCatalogSearch(n) == normalizeCatalogSearch(q)) {
        _supplierDirectoryId = m['id']?.toString();
        _supplierFuzzySuggestion = null;
        return;
      }
    }
    _supplierDirectoryId = null;
    final ranked = catalogFuzzyRank(
      q,
      suppliers,
      (m) => m['name']?.toString() ?? '',
      minScore: 82,
      limit: 1,
    );
    if (ranked.isEmpty) {
      _supplierFuzzySuggestion = null;
      return;
    }
    final top = ranked.first;
    final name = top['name']?.toString().trim() ?? '';
    if (name.isEmpty ||
        normalizeCatalogSearch(name) == normalizeCatalogSearch(q) ||
        catalogFuzzyScore(q, name) < 88) {
      _supplierFuzzySuggestion = null;
      return;
    }
    _supplierFuzzySuggestion = top;
  }

  void _refreshBrokerDirectoryLink() {
    final q = _brokerCtrl.text.trim();
    if (q.isEmpty) {
      _brokerDirectoryId = null;
      _brokerFuzzySuggestion = null;
      return;
    }
    final brokers = ref.read(brokersListProvider).valueOrNull ?? [];
    for (final m in brokers) {
      final n = m['name']?.toString().trim() ?? '';
      if (n.isEmpty) continue;
      if (normalizeCatalogSearch(n) == normalizeCatalogSearch(q)) {
        _brokerDirectoryId = m['id']?.toString();
        _brokerFuzzySuggestion = null;
        return;
      }
    }
    _brokerDirectoryId = null;
    final ranked = catalogFuzzyRank(
      q,
      brokers,
      (m) => m['name']?.toString() ?? '',
      minScore: 82,
      limit: 1,
    );
    if (ranked.isEmpty) {
      _brokerFuzzySuggestion = null;
      return;
    }
    final top = ranked.first;
    final name = top['name']?.toString().trim() ?? '';
    if (name.isEmpty ||
        normalizeCatalogSearch(name) == normalizeCatalogSearch(q) ||
        catalogFuzzyScore(q, name) < 88) {
      _brokerFuzzySuggestion = null;
      return;
    }
    _brokerFuzzySuggestion = top;
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src);
    if (x == null) return;
    final raw = await x.readAsBytes();
    for (final old in _rows) {
      old.dispose();
    }
    setState(() {
      _jpegBytes = null;
      _rows = [];
      _missing.clear();
      _note = null;
      _legacyScanConfidence = null;
      _legacyHasTotalMismatch = false;
      _legacyParseWarnings = [];
      _supplierCtrl.clear();
      _supplierDirectoryId = null;
      _supplierFuzzySuggestion = null;
      _brokerCtrl.clear();
      _brokerDirectoryId = null;
      _brokerFuzzySuggestion = null;
      _deliveredCtrl.clear();
      _billtyCtrl.clear();
      _freightCtrl.clear();
      _freightType = 'separate';
      _userConfirmedPreview = false;
    });
    try {
      final compressed = await _compressForUpload(raw);
      setState(() => _jpegBytes = compressed);
    } catch (_) {
      setState(() => _jpegBytes = raw);
    }
  }

  Future<List<int>> _compressForUpload(List<int> raw) async {
    final decoded = img.decodeImage(Uint8List.fromList(raw));
    if (decoded == null) return Uint8List.fromList(raw);
    const maxW = 1600;
    final resized =
        decoded.width > maxW ? img.copyResize(decoded, width: maxW) : decoded;
    return List<int>.from(img.encodeJpg(resized, quality: 82));
  }

  Future<void> _scan() async {
    final session = ref.read(sessionProvider);
    if (session == null || _jpegBytes == null || _jpegBytes!.isEmpty) return;
    setState(() {
      _busy = true;
      _note = null;
      _legacyScanConfidence = null;
      _legacyHasTotalMismatch = false;
      _legacyParseWarnings = [];
    });
    try {
      final res = await ref.read(hexaApiProvider).scanPurchaseBillMultipart(
            businessId: session.primaryBusiness.id,
            imageBytes: _jpegBytes!,
            filename: 'bill_scan.jpg',
          );
      final miss = res['missing_fields'];
      final nextMiss = <String>{};
      if (miss is List) {
        for (final e in miss) {
          nextMiss.add(e.toString());
        }
      }
      final supplier = res['supplier_name']?.toString().trim();
      _supplierCtrl.text = supplier ?? '';
      final broker = res['broker_name']?.toString().trim();
      _brokerCtrl.text = broker ?? '';
      final sid = res['supplier_id']?.toString().trim();
      final bid = res['broker_id']?.toString().trim();
      final charges = res['charges'];
      if (charges is Map) {
        final ch = Map<String, dynamic>.from(charges);
        _deliveredCtrl.text = (ch['delivered_rate'] as num?)?.toString() ?? '';
        _billtyCtrl.text = (ch['billty_rate'] as num?)?.toString() ?? '';
        _freightCtrl.text = (ch['freight_amount'] as num?)?.toString() ?? '';
        final ft = ch['freight_type']?.toString();
        if (ft == 'included' || ft == 'separate') _freightType = ft!;
      }
      final items = res['items'];
      final nextRows = <_BillRowEdit>[];
      if (items is List) {
        for (final e in items) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          var u = m['unit']?.toString().trim().toLowerCase() ?? '';
          if (u == 'unit' || u == 'pcs' || u == 'pc') u = 'piece';
          nextRows.add(
            _BillRowEdit(
              catalogItemId: m['catalog_item_id']?.toString().trim().isNotEmpty == true
                  ? m['catalog_item_id']?.toString().trim()
                  : null,
              name: TextEditingController(text: m['name']?.toString() ?? ''),
              qty: TextEditingController(
                text: _fmtQty((m['qty'] as num?)?.toDouble() ?? 1),
              ),
              unit:
                  TextEditingController(text: u.isEmpty ? 'kg' : u),
              pRate: TextEditingController(
                text: ((m['purchase_rate'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
              ),
              sRate: TextEditingController(
                text: ((m['selling_rate'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
              ),
              kgPerUnit: TextEditingController(
                text: ((m['weight_per_unit_kg'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      for (final old in _rows) {
        old.dispose();
      }
      final meta = res['meta'];
      final warns = <String>[];
      if (meta is Map) {
        final pw = meta['parse_warnings'];
        if (pw is List) {
          for (final w in pw) {
            final t = w?.toString().trim() ?? '';
            if (t.isNotEmpty) warns.add(t);
          }
        }
      }
      final legacyTotalMismatch =
          warns.any((w) => w.toUpperCase().contains('TOTAL_MISMATCH'));
      final overallConf = (res['confidence'] is num)
          ? (res['confidence'] as num).toDouble()
          : double.tryParse(res['confidence']?.toString() ?? '') ?? 0.0;
      setState(() {
        _missing.clear();
        _missing.addAll(nextMiss);
        _rows = nextRows.isEmpty ? [_BillRowEdit.empty()] : nextRows;
        final baseNote = (res['note']?.toString() ?? '').trim();
        _note = baseNote.isEmpty ? null : baseNote;
        _legacyParseWarnings = List<String>.from(warns);
        _legacyScanConfidence = overallConf;
        _legacyHasTotalMismatch = legacyTotalMismatch;
        _userConfirmedPreview = false;
        if (sid != null && sid.isNotEmpty) {
          _supplierDirectoryId = sid;
          _supplierFuzzySuggestion = null;
        }
        if (bid != null && bid.isNotEmpty) {
          _brokerDirectoryId = bid;
          _brokerFuzzySuggestion = null;
        }
        _refreshSupplierDirectoryLink();
        _refreshBrokerDirectoryLink();
      });
      HapticFeedback.selectionClick();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyCatalogRowToBillRow(_BillRowEdit r, Map<String, dynamic> row) {
    final nm = (row['name'] ?? '').toString().trim();
    if (nm.isNotEmpty) r.name.text = nm;
    final id = row['id']?.toString().trim();
    r.catalogItemId = (id != null && id.isNotEmpty) ? id : null;
    final du = (row['default_unit'] ?? '').toString().toLowerCase().trim();
    if (du == 'bag' || du == 'sack') {
      r.unit.text = 'bag';
    } else if (du == 'box') {
      r.unit.text = 'box';
    } else if (du == 'tin') {
      r.unit.text = 'tin';
    } else if (du == 'piece' || du == 'pcs' || du == 'pkt' || du == 'packet') {
      r.unit.text = 'piece';
    } else {
      r.unit.text = 'kg';
    }
    final lpp = row['last_purchase_price'];
    if (lpp is num && lpp > 0 && r.pRate.text.trim().isEmpty) {
      r.pRate.text =
          lpp == lpp.roundToDouble() ? '${lpp.round()}' : '$lpp';
    }
    final lsr = row['last_selling_rate'];
    if (lsr is num && lsr > 0 && r.sRate.text.trim().isEmpty) {
      r.sRate.text =
          lsr == lsr.roundToDouble() ? '${lsr.round()}' : '$lsr';
    }
    final dkg = row['default_kg_per_bag'];
    if ((du == 'bag' || du == 'sack') &&
        dkg is num &&
        dkg > 0 &&
        r.kgPerUnit.text.trim().isEmpty) {
      r.kgPerUnit.text =
          dkg == dkg.roundToDouble() ? '${dkg.round()}' : '$dkg';
    }
  }

  PurchaseDraft buildDraftFromUi() {
    final lines = <PurchaseLineDraft>[];
    for (final r in _rows) {
      final name = r.name.text.trim();
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      final unit = r.unit.text.trim().toLowerCase();
      final rate = double.tryParse(r.pRate.text.trim()) ?? 0;
      final sell = double.tryParse(r.sRate.text.trim()) ?? 0;
      final kpu = double.tryParse(r.kgPerUnit.text.trim()) ?? 0;
      if (name.isEmpty && qty <= 0 && rate <= 0) continue;
      final cid = r.catalogItemId?.trim();
      lines.add(
        PurchaseLineDraft(
          catalogItemId: (cid != null && cid.isNotEmpty) ? cid : null,
          itemName: name.isEmpty ? 'Item' : name,
          qty: qty > 0 ? qty : 1,
          unit: unit.isEmpty ? 'kg' : unit,
          landingCost: rate > 0 ? rate : 0.01,
          sellingPrice: sell > 0 ? sell : null,
          kgPerUnit: kpu > 0 ? kpu : null,
        ),
      );
    }
    return PurchaseDraft(
      purchaseDate: DateTime.now(),
      supplierId: _supplierDirectoryId,
      supplierName: _supplierCtrl.text.trim().isEmpty
          ? null
          : _supplierCtrl.text.trim(),
      brokerId: _brokerDirectoryId,
      brokerName:
          _brokerCtrl.text.trim().isEmpty ? null : _brokerCtrl.text.trim(),
      invoiceNumber: null,
      deliveredRate: double.tryParse(_deliveredCtrl.text.trim()),
      billtyRate: double.tryParse(_billtyCtrl.text.trim()),
      freightAmount: double.tryParse(_freightCtrl.text.trim()),
      freightType: _freightType,
      lines: lines,
    );
  }

  bool _missingSupplier() =>
      _supplierCtrl.text.trim().isEmpty &&
      (_missing.contains('supplier_name') || _rows.isNotEmpty);

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      final copy = List<_BillRowEdit>.from(_rows)..removeAt(i);
      _rows = copy.isEmpty ? [_BillRowEdit.empty()] : copy;
    });
  }

  bool _warnLineCell(int idx, String key) =>
      _missing.contains('line_$idx.$key');

  InputDecoration _lineDeco(String label, {required bool warn}) =>
      InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: warn ? Colors.red : Colors.grey,
            width: warn ? 1.35 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: warn ? Colors.red : Colors.grey[300]!,
            width: warn ? 1.35 : 1,
          ),
        ),
      );

  Widget _supplierField(bool highlight) {
    return TextField(
      controller: _supplierCtrl,
      decoration: InputDecoration(
        labelText: 'Supplier (from bill)',
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey,
            width: highlight ? 1.5 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : HexaColors.brandPrimary,
            width: 1.5,
          ),
        ),
      ),
      onChanged: (_) => setState(() {
        _refreshSupplierDirectoryLink();
      }),
    );
  }

  Widget _brokerField(bool highlight) {
    return TextField(
      controller: _brokerCtrl,
      decoration: InputDecoration(
        labelText: 'Broker (optional)',
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey,
            width: highlight ? 1.5 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : HexaColors.brandPrimary,
            width: 1.5,
          ),
        ),
      ),
      onChanged: (_) => setState(() {
        _refreshBrokerDirectoryLink();
      }),
    );
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _deliveredCtrl.dispose();
    _billtyCtrl.dispose();
    _freightCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool _canApply() {
    if (_supplierDirectoryId == null || _supplierDirectoryId!.trim().isEmpty) {
      return false;
    }
    final b = _brokerCtrl.text.trim();
    if (b.isNotEmpty &&
        (_brokerDirectoryId == null || _brokerDirectoryId!.trim().isEmpty)) {
      return false;
    }
    if (_rows.isEmpty) return false;
    for (final r in _rows) {
      final name = r.name.text.trim();
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      final unit = r.unit.text.trim();
      final pr = double.tryParse(r.pRate.text.trim()) ?? 0;
      if (name.isEmpty || qty <= 0 || unit.isEmpty || pr <= 0) return false;
    }
    return _userConfirmedPreview;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(suppliersListProvider, (previous, next) {
      if (!next.hasValue || !mounted) return;
      if (_supplierCtrl.text.trim().isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _refreshSupplierDirectoryLink());
      });
    });
    ref.listen(brokersListProvider, (previous, next) {
      if (!next.hasValue || !mounted) return;
      if (_brokerCtrl.text.trim().isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _refreshBrokerDirectoryLink());
      });
    });

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (!widget.compactHeading)
                  const Text(
                    'Take or choose a bill photo — preview only until you tap Apply. '
                    'Confirm every row; supplier name may need matching to your directory.',
                    style: TextStyle(height: 1.35, fontSize: 13),
                  )
                else
                  Text(
                    'Scan bill → edit → Apply to this purchase',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                if (_jpegBytes != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.document_scanner_rounded),
                    label: Text(_busy ? 'Scanning…' : 'Extract text'),
                  ),
                ],
                if (_legacyScanConfidence != null) ...[
                  const SizedBox(height: 10),
                  scanReviewConfidenceSummaryCard(
                    context: context,
                    overall: _legacyScanConfidence!,
                    needsReview: _missing.isNotEmpty ||
                        _legacyParseWarnings.isNotEmpty ||
                        ((_legacyScanConfidence ?? 0) < 0.85 && _rows.isNotEmpty),
                    ocrExtractConfidence: null,
                    hasTotalMismatch: _legacyHasTotalMismatch,
                  ),
                  scanReviewLegacyWarningsList(context, _legacyParseWarnings),
                ],
                if (_note != null && _note!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _note!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Review',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _supplierField(_missingSupplier()),
                if (_supplierDirectoryId != null &&
                    _supplierCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Matched to a supplier in your directory',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
                if (_supplierFuzzySuggestion != null) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        final m = _supplierFuzzySuggestion!;
                        final name = m['name']?.toString().trim() ?? '';
                        final id = m['id']?.toString();
                        setState(() {
                          _supplierCtrl.text = name;
                          _supplierDirectoryId = id;
                          _supplierFuzzySuggestion = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(Icons.merge_type_rounded,
                                color: Colors.amber.shade900, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Similar directory supplier',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  Text(
                                    '${_supplierFuzzySuggestion!['name']} — tap to link (avoid duplicate)',
                                    style:
                                        const TextStyle(fontSize: 11, height: 1.25),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade700),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _brokerField(
                  _brokerCtrl.text.trim().isNotEmpty &&
                      (_brokerDirectoryId == null ||
                          _brokerDirectoryId!.trim().isEmpty),
                ),
                if (_brokerDirectoryId != null &&
                    _brokerCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Matched to a broker in your directory',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ],
                if (_brokerFuzzySuggestion != null) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        final m = _brokerFuzzySuggestion!;
                        final name = m['name']?.toString().trim() ?? '';
                        final id = m['id']?.toString();
                        setState(() {
                          _brokerCtrl.text = name;
                          _brokerDirectoryId = id;
                          _brokerFuzzySuggestion = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(Icons.merge_type_rounded,
                                color: Colors.amber.shade900, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Similar directory broker',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  Text(
                                    '${_brokerFuzzySuggestion!['name']} — tap to link (avoid duplicate)',
                                    style:
                                        const TextStyle(fontSize: 11, height: 1.25),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade700),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Charges (optional)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: [
                    TextField(
                      controller: _deliveredCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Delivered (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _billtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Billty (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _freightCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Freight (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _freightType,
                      decoration: const InputDecoration(
                        labelText: 'Freight type',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'separate', child: Text('Separate')),
                        DropdownMenuItem(value: 'included', child: Text('Included')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _freightType = v);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                if (_rows.isEmpty)
                  const Text(
                    'No lines yet — scan or add rows manually.',
                    style: TextStyle(fontSize: 12),
                  )
                else
                  ..._rows.asMap().entries.map((e) {
                    final i = e.key;
                    final r = e.value;
                    final rowWarn = _missing.any((m) => m.startsWith('line_$i.'));
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: rowWarn
                              ? Colors.red.withValues(alpha: 0.65)
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text('Line ${i + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => _removeRow(i),
                                ),
                              ],
                            ),
                            _BillLineCatalogNameBlock(
                              nameCtrl: r.name,
                              supplierDirectoryId: _supplierDirectoryId,
                              decoration: _lineDeco('Item name',
                                  warn: _warnLineCell(i, 'item_name')),
                              onPick: (row) => setState(() {
                                _applyCatalogRowToBillRow(r, row);
                              }),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: r.qty,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _lineDeco('Qty',
                                        warn: _warnLineCell(i, 'qty')),
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: r.unit,
                                    decoration: _lineDeco('Unit',
                                        warn: _warnLineCell(i, 'unit')),
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: r.kgPerUnit,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration:
                                        _lineDeco('Kg/unit', warn: false),
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: r.pRate,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: _lineDeco('P rate',
                                        warn: _warnLineCell(i, 'purchase_rate')),
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: r.sRate,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration:
                                        _lineDeco('S rate', warn: false),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _rows = [..._rows, _BillRowEdit.empty()]);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add blank line'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _userConfirmedPreview,
            onChanged: (_supplierDirectoryId != null &&
                    _rows.isNotEmpty &&
                    (_brokerCtrl.text.trim().isEmpty ||
                        (_brokerDirectoryId != null &&
                            _brokerDirectoryId!.trim().isNotEmpty)))
                ? (v) => setState(() => _userConfirmedPreview = v ?? false)
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I confirm supplier + all item rows are correct',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            subtitle: Text(
              _supplierDirectoryId == null
                  ? 'Supplier must be matched to your directory (tap the suggestion if shown).'
                  : (_brokerCtrl.text.trim().isNotEmpty &&
                          (_brokerDirectoryId == null ||
                              _brokerDirectoryId!.trim().isEmpty))
                      ? 'Broker name is filled — match it to your directory (or clear the field).'
                      : 'Required: item, qty, unit, and purchase rate for each row.',
              style: const TextStyle(fontSize: 11, height: 1.25),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_rows.any((r) => r.name.text.trim().isNotEmpty) ||
                    _supplierCtrl.text.trim().isNotEmpty)
                ? (_canApply()
                    ? () {
                        widget.onApplyDraft(buildDraftFromUi());
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cannot apply yet: match supplier + fill required fields, then tick confirmation.',
                            ),
                          ),
                        );
                      })
                : null,
            icon: Icon(widget.applyButtonIcon),
            label: Text(widget.applyButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _BillLineCatalogNameBlock extends ConsumerStatefulWidget {
  const _BillLineCatalogNameBlock({
    required this.nameCtrl,
    required this.supplierDirectoryId,
    required this.decoration,
    required this.onPick,
  });

  final TextEditingController nameCtrl;
  final String? supplierDirectoryId;
  final InputDecoration decoration;
  final void Function(Map<String, dynamic> row) onPick;

  @override
  ConsumerState<_BillLineCatalogNameBlock> createState() =>
      _BillLineCatalogNameBlockState();
}

class _BillLineCatalogNameBlockState
    extends ConsumerState<_BillLineCatalogNameBlock> {
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final session = ref.read(sessionProvider);
    if (session == null || q.isEmpty) {
      setState(() => _items = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await ref.read(hexaApiProvider).unifiedSearch(
            businessId: session.primaryBusiness.id,
            q: q,
            supplierId: widget.supplierDirectoryId,
          );
      final raw = data['catalog_items'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw.take(12)) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) setState(() => _items = list);
    } on DioException {
      if (mounted) setState(() => _items = []);
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() => _items = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(q));
  }

  void _apply(Map<String, dynamic> row) {
    widget.onPick(row);
    setState(() => _items = []);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.nameCtrl,
          decoration: widget.decoration.copyWith(
            hintText: 'Type to search catalog (same as AI scan flow)',
          ),
          onChanged: _onChanged,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final row = _items[i];
                    final name = (row['name'] ?? '').toString();
                    final unit = (row['default_unit'] ?? '—').toString();
                    final lpp = row['last_purchase_price'];
                    final lsn =
                        (row['last_supplier_name'] ?? '').toString().trim();
                    final rateStr = (lpp is num && lpp > 0)
                        ? ' · last P ₹${lpp is int || lpp == lpp.roundToDouble() ? lpp.round() : lpp}'
                        : '';
                    final supStr =
                        lsn.isNotEmpty ? ' · $lsn' : '';
                    return ListTile(
                      dense: true,
                      title: Text(name,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '$unit$supStr$rateStr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _apply(row),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BillRowEdit {
  _BillRowEdit({
    this.catalogItemId,
    required this.name,
    required this.qty,
    required this.unit,
    required this.pRate,
    required this.sRate,
    required this.kgPerUnit,
  });

  factory _BillRowEdit.empty() {
    return _BillRowEdit(
      catalogItemId: null,
      name: TextEditingController(),
      qty: TextEditingController(text: '1'),
      unit: TextEditingController(text: 'kg'),
      pRate: TextEditingController(),
      sRate: TextEditingController(),
      kgPerUnit: TextEditingController(),
    );
  }

  String? catalogItemId;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController unit;
  final TextEditingController pRate;
  final TextEditingController sRate;
  final TextEditingController kgPerUnit;

  void dispose() {
    name.dispose();
    qty.dispose();
    unit.dispose();
    pRate.dispose();
    sRate.dispose();
    kgPerUnit.dispose();
  }
}
