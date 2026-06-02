import 'dart:isolate';
import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/config/app_config.dart';
import '../../../core/json_coerce.dart';
import '../../../core/services/pdf_text_safe.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum LabelSize { small, medium, large }

/// Primary symbology on printed labels (Sprint 15).
enum BarcodeSymbolMode { code128, qrCode, code128WithQr }

class BarcodeLabelData {
  const BarcodeLabelData({
    required this.itemCode,
    required this.itemName,
    this.barcode,
    this.publicToken,
    this.unit,
    this.currentStock,
    this.lastPurchaseDate,
    this.lastPurchaseQty,
    this.lastPurchaseUnit,
    this.lastPurchaseRate,
    this.supplierName,
  });

  /// Scannable packaging barcode (Code128/QR payload).
  final String? barcode;
  /// Public scan token for QR URL labels.
  final String? publicToken;
  /// Internal shelf / ERP code (printed as text).
  final String itemCode;
  final String itemName;
  final String? unit;
  final double? currentStock;
  final DateTime? lastPurchaseDate;
  final double? lastPurchaseQty;
  final String? lastPurchaseUnit;
  final double? lastPurchaseRate;
  final String? supplierName;

  /// Value encoded in the barcode image (barcode column, else item_code).
  String get symbologyValue {
    final b = barcode?.trim() ?? '';
    if (b.isNotEmpty) return BarcodePdfService.sanitizePrintPayload(b);
    return BarcodePdfService.sanitizePrintPayload(itemCode.trim());
  }

  /// QR payload (browser scan route), fallback to barcode or item code.
  String? qrScanUrl(String webBase) {
    final key = (publicToken?.trim().isNotEmpty == true)
        ? publicToken!.trim()
        : (barcode?.trim().isNotEmpty == true)
            ? barcode!.trim()
            : itemCode.trim();
    if (key.isEmpty) return null;
    final base = webBase.endsWith('/') ? webBase.substring(0, webBase.length - 1) : webBase;
    return '$base/item/${Uri.encodeComponent(key)}';
  }

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'itemCode': itemCode,
        'itemName': itemName,
        'unit': unit,
        'currentStock': currentStock,
        'lastPurchaseDate': lastPurchaseDate?.toUtc().toIso8601String(),
        'lastPurchaseQty': lastPurchaseQty,
        'lastPurchaseUnit': lastPurchaseUnit,
        'lastPurchaseRate': lastPurchaseRate,
        'supplierName': supplierName,
      };

  /// Drops NaN/Infinity so PDF layout never calls [double.toInt] on bad API values.
  static double? finiteQty(double? v) {
    if (v == null || !v.isFinite) return null;
    return v;
  }

  factory BarcodeLabelData.fromJson(Map<String, dynamic> j) {
    DateTime? lpDate;
    final lpRaw = j['lastPurchaseDate'];
    if (lpRaw is String && lpRaw.isNotEmpty) {
      lpDate = DateTime.tryParse(lpRaw);
    }
    return BarcodeLabelData(
      barcode: j['barcode'] as String?,
      itemCode: j['itemCode'] as String? ?? '',
      itemName: j['itemName'] as String? ?? '',
      unit: j['unit'] as String?,
      currentStock: finiteQty(coerceToDoubleNullable(j['currentStock'])),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: finiteQty(coerceToDoubleNullable(j['lastPurchaseQty'])),
      lastPurchaseUnit: j['lastPurchaseUnit'] as String?,
      lastPurchaseRate: finiteQty(coerceToDoubleNullable(j['lastPurchaseRate'])),
      supplierName: j['supplierName'] as String?,
    );
  }

  static BarcodeLabelData? fromApiMap(Map<String, dynamic> j) {
    final ic = j['item_code']?.toString().trim() ?? '';
    final bc = j['barcode']?.toString().trim() ?? '';
    if (ic.isEmpty && bc.isEmpty) return null;
    DateTime? lpDate;
    final lpRaw = j['last_purchase_date'];
    if (lpRaw is String && lpRaw.isNotEmpty) {
      lpDate = DateTime.tryParse(lpRaw);
    }
    return BarcodeLabelData(
      barcode: bc.isEmpty ? null : bc,
      itemCode: ic.isEmpty ? bc : ic,
      itemName: j['item_name']?.toString() ?? (ic.isNotEmpty ? ic : bc),
      unit: j['unit']?.toString(),
      currentStock: finiteQty(coerceToDoubleNullable(j['current_stock'])),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: finiteQty(coerceToDoubleNullable(j['last_purchase_qty'])),
      lastPurchaseUnit: j['last_purchase_unit']?.toString(),
      lastPurchaseRate: finiteQty(coerceToDoubleNullable(j['last_purchase_rate'])),
      supplierName: j['supplier_name']?.toString(),
    );
  }
}

class BarcodePdfService {
  /// Safe qty text for PDF (avoids `Infinity.toInt()` on bad doubles).
  static String? pdfQtyDisplayString(double? qty) {
    final q = BarcodeLabelData.finiteQty(qty);
    if (q == null || q <= 0) return null;
    final rounded = q.roundToDouble();
    if (!rounded.isFinite) return null;
    if ((q - rounded).abs() < 0.001) {
      final asInt = rounded.round();
      return asInt.isFinite ? '$asInt' : null;
    }
    return q.toStringAsFixed(1);
  }

  /// Strip characters that break Code128 / overflow QR on web PDF.
  static String sanitizePrintPayload(String raw, {bool forQr = false}) {
    var s = raw.trim();
    if (s.isEmpty) return '0';
    if (forQr) {
      return s.length > 180 ? s.substring(0, 180) : s;
    }
    final buf = StringBuffer();
    for (final unit in s.codeUnits) {
      if (unit >= 32 && unit <= 126) {
        buf.writeCharCode(unit);
      }
    }
    final out = buf.toString();
    if (out.isEmpty) return '0';
    return out.length > 48 ? out.substring(0, 48) : out;
  }

  static String _symbologyValue(
    BarcodeLabelData data, {
    BarcodeSymbolMode symbol = BarcodeSymbolMode.code128,
    String? webBase,
  }) {
    if (symbol == BarcodeSymbolMode.qrCode && webBase != null) {
      final url = data.qrScanUrl(webBase);
      if (url != null && url.isNotEmpty) {
        return sanitizePrintPayload(url, forQr: true);
      }
    }
    final v = data.symbologyValue;
    if (v.isEmpty || v == '0') {
      throw BarcodeOperationException(
        'Barcode image missing for "${data.itemName}".',
        kind: BarcodeOperationKind.barcodeRender,
      );
    }
    return v;
  }

  static List<BarcodeLabelData> dedupeLabels(List<BarcodeLabelData> items) {
    final seen = <String>{};
    final out = <BarcodeLabelData>[];
    for (final d in items) {
      final key =
          '${d.itemCode.trim()}|${d.barcode?.trim() ?? ''}|${d.itemName.trim()}';
      if (seen.add(key)) out.add(d);
    }
    return out;
  }

  static List<BarcodeLabelData> _requirePrintable(List<BarcodeLabelData> items) {
    final ok = <BarcodeLabelData>[];
    for (final d in items) {
      try {
        _symbologyValue(d);
        ok.add(d);
      } catch (_) {
        // skip invalid row in batch; caller handles empty
      }
    }
    if (ok.isEmpty) {
      throw BarcodeOperationException(
        'No valid barcodes to print. Assign barcodes or item codes first.',
        kind: BarcodeOperationKind.barcodeRender,
      );
    }
    return ok;
  }

  static Future<Uint8List> generateSingleLabel({
    required BarcodeLabelData data,
    LabelSize size = LabelSize.small,
    int copies = 1,
    bool showLastPurchase = true,
    bool hideFinancials = false,
  }) async {
    _symbologyValue(data);
    final doc = pw.Document();
    final fmt = _pageFormat(size);
    for (var c = 0; c < copies; c++) {
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: _labelBody(
              data: data,
              size: size,
              showLastPurchase: showLastPurchase,
              hideFinancials: hideFinancials,
              showStockOnLabel: true,
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> generateBatch({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.small,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
    bool hideFinancials = false,
    bool showStockOnLabel = true,
    int labelsPerRow = 1,
    BarcodeSymbolMode symbol = BarcodeSymbolMode.code128WithQr,
  }) async {
    final printable = _requirePrintable(items);
    final expanded = <BarcodeLabelData>[];
    for (final data in printable) {
      for (var c = 0; c < copiesPerItem; c++) {
        expanded.add(data);
      }
    }
    final perRow = labelsPerRow.clamp(1, 3);
    final doc = pw.Document();

    if (perRow <= 1) {
      final fmt = _pageFormat(size);
      for (final data in expanded) {
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: _labelBody(
                data: data,
                size: size,
                showLastPurchase: showLastPurchase,
                hideFinancials: hideFinancials,
                showStockOnLabel: showStockOnLabel,
                symbol: symbol,
              ),
            ),
          ),
        );
      }
      return doc.save();
    }

    final labelFmt = _pageFormat(size);
    const sheet = PdfPageFormat.a4;
    for (var i = 0; i < expanded.length; i += perRow) {
      final row = expanded.skip(i).take(perRow).toList();
      doc.addPage(
        pw.Page(
          pageFormat: sheet,
          margin: const pw.EdgeInsets.all(10),
          build: (ctx) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final d in row)
                pw.Expanded(
                  child: pw.Container(
                    height: labelFmt.height + 8,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.4,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: _labelBody(
                        data: d,
                        size: size,
                        showLastPurchase: showLastPurchase,
                        hideFinancials: hideFinancials,
                        showStockOnLabel: showStockOnLabel,
                        symbol: symbol,
                      ),
                    ),
                  ),
                ),
              for (var pad = row.length; pad < perRow; pad++)
                pw.Expanded(child: pw.SizedBox()),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Maximizes labels per A4 page: 5mm margins, 2mm gaps; cell size 30×10 (S),
  /// 50×25 (M), 80×40 (L). Runs off the UI thread on VM via [Isolate.run].
  /// PDF-safe display text (WinAnsi fonts cannot render ₹, em dash, etc.).
  static String pdfLabelText(String? raw) => safePdfText(raw);

  static Future<Uint8List> generateBatchA4Dense({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.small,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
    bool hideFinancials = false,
    bool showStockOnLabel = true,
    int columns = 4,
    /// When set, fits about this many stickers per A4 page (e.g. 50).
    int? targetLabelsPerPage,
    BarcodeSymbolMode symbol = BarcodeSymbolMode.code128WithQr,
    /// Global serial for first label in this PDF (1-based).
    int serialStart = 1,
    /// Total labels in full batch (for page header "3 of 556").
    int? totalLabelCount,
  }) async {
    final printable = _requirePrintable(dedupeLabels(items));
    final expanded = <BarcodeLabelData>[];
    for (final data in printable) {
      for (var c = 0; c < copiesPerItem; c++) {
        expanded.add(data);
      }
    }
    final payload = <String, dynamic>{
      'labels': [for (final e in expanded) e.toJson()],
      'size': size.index,
      'showLastPurchase': showLastPurchase,
      'hideFinancials': hideFinancials,
      'showStockOnLabel': showStockOnLabel,
      'maxCols': columns.clamp(1, 6),
      if (targetLabelsPerPage != null)
        'targetLabelsPerPage': targetLabelsPerPage.clamp(20, 60),
      'symbol': symbol.index,
      'serialStart': serialStart,
      if (totalLabelCount != null) 'totalLabelCount': totalLabelCount,
    };
    try {
      if (kIsWeb) {
        return await _barcodeA4DenseFromPayload(payload);
      }
      return await Isolate.run(() => _barcodeA4DenseFromPayload(payload));
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (symbol == BarcodeSymbolMode.qrCode) {
        return await generateBatchA4Dense(
          items: items,
          size: size,
          copiesPerItem: copiesPerItem,
          showLastPurchase: showLastPurchase,
          hideFinancials: hideFinancials,
          showStockOnLabel: showStockOnLabel,
          columns: columns,
          targetLabelsPerPage: targetLabelsPerPage,
          symbol: BarcodeSymbolMode.code128,
          serialStart: serialStart,
          totalLabelCount: totalLabelCount,
        );
      }
      rethrow;
    }
  }

  static (double wMm, double hMm) a4DenseCellMm(LabelSize size) => switch (size) {
        LabelSize.small => (30.0, 10.0),
        LabelSize.medium => (50.0, 25.0),
        LabelSize.large => (80.0, 40.0),
      };

  /// PDF builder for [Isolate.run] / web (uses async [pw.Document.save]).
  static Future<Uint8List> buildA4DenseGridPdf(Map<String, dynamic> payload) async {
    final rawList = payload['labels'] as List<dynamic>;
    final labels = <BarcodeLabelData>[
      for (final e in rawList)
        BarcodeLabelData.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    final sizeIdx = (payload['size'] as int?) ?? 1;
    final size = LabelSize.values[sizeIdx.clamp(0, LabelSize.values.length - 1)];
    final showLastPurchase = payload['showLastPurchase'] as bool? ?? true;
    final hideFinancials = payload['hideFinancials'] as bool? ?? false;
    final showStockOnLabel = payload['showStockOnLabel'] as bool? ?? true;
    final symbolIdx = (payload['symbol'] as int?) ?? BarcodeSymbolMode.code128WithQr.index;
    final symbol = BarcodeSymbolMode.values[
        symbolIdx.clamp(0, BarcodeSymbolMode.values.length - 1)];

    final mm = PdfPageFormat.mm;
    const margin = 5.0 * PdfPageFormat.mm;
    const gap = 4.0 * PdfPageFormat.mm;
    const sheet = PdfPageFormat.a4;
    final innerW = sheet.width - 2 * margin;
    final innerH = sheet.height - 2 * margin;

    final targetPerPage = payload['targetLabelsPerPage'] as int?;
    final serialStart = (payload['serialStart'] as int?) ?? 1;
    final totalLabelCount = payload['totalLabelCount'] as int?;
    late final int cols;
    late final int rows;
    late final double labelW;
    late final double labelH;
    late final int perPage;
    late final LabelSize cellSize;

    if (targetPerPage != null && targetPerPage > 0) {
      final target = targetPerPage.clamp(20, 60);
      cols = switch (target) {
        <= 32 => 4,
        <= 42 => 4,
        <= 50 => 5,
        _ => 6,
      };
      rows = math.max(1, (target / cols).ceil().clamp(1, 12));
      perPage = cols * rows;
      labelW = (innerW - (cols - 1) * gap) / cols;
      labelH = (innerH - (rows - 1) * gap) / rows;
      final hMm = labelH / mm;
      cellSize = hMm < 14 ? LabelSize.small : LabelSize.medium;
    } else {
      final (lwMm, lhMm) = a4DenseCellMm(size);
      labelW = lwMm * mm;
      labelH = lhMm * mm;
      cellSize = size;
      final maxCols = (payload['maxCols'] as int?) ?? 4;
      cols = math.min(
        maxCols,
        math.max(1, ((innerW + gap) / (labelW + gap)).floor()),
      );
      rows = math.max(1, ((innerH + gap) / (labelH + gap)).floor());
      perPage = cols * rows;
    }

    final clamped = _clampLabelDimensions(labelW, labelH);
    final safeLabelW = clamped.$1;
    final safeLabelH = clamped.$2;
    if (cols < 1 || rows < 1 || perPage < 1) {
      throw StateError(
        'Invalid A4 label grid ($cols×$rows, ${safeLabelW}x$safeLabelH)',
      );
    }

    final doc = pw.Document();
    final compact = targetPerPage != null && targetPerPage > 0;
    for (var base = 0; base < labels.length; base += perPage) {
      if (kIsWeb && base > 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final chunk = labels.sublist(base, math.min(base + perPage, labels.length));
      final pageFirstSl = serialStart + base;
      final pageLastSl = serialStart + base + chunk.length - 1;
      doc.addPage(
        pw.Page(
          pageFormat: sheet,
          margin: const pw.EdgeInsets.all(margin),
          build: (ctx) {
            final pageRows = <pw.Widget>[];
            for (var r = 0; r < rows; r++) {
              final rowCells = <pw.Widget>[];
              for (var c = 0; c < cols; c++) {
                final idx = r * cols + c;
                final right = c < cols - 1 ? gap : 0.0;
                final bottom = r < rows - 1 ? gap : 0.0;
                if (idx < chunk.length) {
                  final sl = pageFirstSl + idx;
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: _safeTableLabelCell(
                        width: safeLabelW,
                        height: safeLabelH,
                        data: chunk[idx],
                        serialNumber: sl,
                        cellSize: cellSize,
                        showLastPurchase: showLastPurchase,
                        hideFinancials: hideFinancials,
                        showStockOnLabel: showStockOnLabel,
                        symbol: symbol,
                        compact: compact,
                      ),
                    ),
                  );
                } else {
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: pw.Container(
                        width: safeLabelW,
                        height: safeLabelH,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.grey300,
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }
              pageRows.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 10,
                      height: safeLabelH,
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        '${r + 1}',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                    ...rowCells,
                  ],
                ),
              );
            }
            final header = pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              margin: const pw.EdgeInsets.only(bottom: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 0.6),
                color: PdfColors.grey100,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Harisree Warehouse',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    totalLabelCount != null
                        ? pdfLabelText(
                            'SL $pageFirstSl-$pageLastSl of $totalLabelCount',
                          )
                        : pdfLabelText('SL $pageFirstSl-$pageLastSl'),
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Cut on box borders',
                    style: pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
                  ),
                ],
              ),
            );
            final colHeader = pw.Padding(
              padding: const pw.EdgeInsets.only(left: 10, bottom: 2),
              child: pw.Row(
                children: [
                  for (var c = 0; c < cols; c++)
                    pw.SizedBox(
                      width: safeLabelW + (c < cols - 1 ? gap : 0),
                      child: pw.Center(
                        child: pw.Text(
                          '${c + 1}',
                          style: pw.TextStyle(
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                header,
                colHeader,
                ...pageRows,
              ],
            );
          },
        ),
      );
    }
    return doc.save();
  }

  static PdfPageFormat _pageFormat(LabelSize size) => switch (size) {
        LabelSize.small =>
          const PdfPageFormat(30 * PdfPageFormat.mm, 10 * PdfPageFormat.mm),
        LabelSize.large =>
          const PdfPageFormat(100 * PdfPageFormat.mm, 50 * PdfPageFormat.mm),
        LabelSize.medium =>
          const PdfPageFormat(50 * PdfPageFormat.mm, 25 * PdfPageFormat.mm),
      };

  static (double titleSize, double codeSize, double bcHeight, double qrSize)
      _sizes(LabelSize size) => switch (size) {
            LabelSize.small => (5.0, 4.0, 12.0, 0.0),
            LabelSize.large => (10.0, 8.0, 40.0, 36.0),
            LabelSize.medium => (8.0, 7.0, 36.0, 28.0),
          };

  static const double _minLabelW = 12.0;
  static const double _minLabelH = 8.0;

  static (double w, double h) _clampLabelDimensions(double w, double h) {
    final mm = PdfPageFormat.mm;
    final safeW = math.max(w, _minLabelW * mm);
    final safeH = math.max(h, _minLabelH * mm);
    if (!safeW.isFinite || !safeH.isFinite || safeW <= 0 || safeH <= 0) {
      return (30.0 * mm, 10.0 * mm);
    }
    return (safeW, safeH);
  }

  static pw.Widget _safeTableLabelCell({
    required double width,
    required double height,
    required BarcodeLabelData data,
    required int serialNumber,
    required LabelSize cellSize,
    required bool showLastPurchase,
    required bool hideFinancials,
    required bool showStockOnLabel,
    required BarcodeSymbolMode symbol,
    required bool compact,
  }) {
    try {
      return _tableLabelCell(
        width: width,
        height: height,
        data: data,
        serialNumber: serialNumber,
        cellSize: cellSize,
        showLastPurchase: showLastPurchase,
        hideFinancials: hideFinancials,
        showStockOnLabel: showStockOnLabel,
        symbol: symbol,
        compact: compact,
      );
    } catch (_) {
      return pw.Container(
        width: width,
        height: height,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.red300, width: 0.75),
          color: PdfColors.grey100,
        ),
        child: pw.Text(
          'SL $serialNumber\nSkip',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 6, color: PdfColors.red800),
        ),
      );
    }
  }

  /// Bordered grid cell with serial number badge (A4 table layout).
  static pw.Widget _tableLabelCell({
    required double width,
    required double height,
    required BarcodeLabelData data,
    required int serialNumber,
    required LabelSize cellSize,
    required bool showLastPurchase,
    required bool hideFinancials,
    required bool showStockOnLabel,
    required BarcodeSymbolMode symbol,
    required bool compact,
  }) {
    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.fromLTRB(2, 1, 2, 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.75),
        color: PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.5),
                  color: PdfColors.grey200,
                ),
                child: pw.Text(
                  'SL $serialNumber',
                  style: pw.TextStyle(
                    fontSize: compact ? 5.5 : 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  data.itemCode.trim().isEmpty
                      ? ''
                      : pdfLabelText(data.itemCode.trim()),
                  maxLines: 1,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: compact ? 4.5 : 6),
                ),
              ),
            ],
          ),
          pw.Expanded(
            child: _labelBodyContainer(
              height: height,
              compact: compact,
              data: data,
              cellSize: cellSize,
              showLastPurchase: showLastPurchase,
              hideFinancials: hideFinancials,
              showStockOnLabel: showStockOnLabel,
              symbol: symbol,
              serialNumber: serialNumber,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _labelBodyContainer({
    required double height,
    required bool compact,
    required BarcodeLabelData data,
    required LabelSize cellSize,
    required bool showLastPurchase,
    required bool hideFinancials,
    required bool showStockOnLabel,
    required BarcodeSymbolMode symbol,
    int? serialNumber,
  }) {
    final body = _labelBody(
      data: data,
      size: cellSize,
      showLastPurchase: showLastPurchase,
      hideFinancials: hideFinancials,
      showStockOnLabel: showStockOnLabel,
      symbol: symbol,
      compact: compact,
      serialNumber: serialNumber,
      showSerialBadge: false,
    );
    // Dense A4 grids: never use FittedBox — it can scale to Infinity on web.
    if (compact) {
      return pw.Align(
        alignment: pw.Alignment.topCenter,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: body,
        ),
      );
    }
    return pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: pw.Alignment.topCenter,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: body,
      ),
    );
  }

  static List<pw.Widget> _labelBody({
    required BarcodeLabelData data,
    required LabelSize size,
    required bool showLastPurchase,
    bool hideFinancials = false,
    bool showStockOnLabel = true,
    BarcodeSymbolMode symbol = BarcodeSymbolMode.code128WithQr,
    bool compact = false,
    int? serialNumber,
    bool showSerialBadge = true,
  }) {
    if (size == LabelSize.small) {
      return [
        _smallThermalLabelRow(
          data: data,
          symbol: symbol,
          showLastPurchase: showLastPurchase,
          compact: compact,
          serialNumber: serialNumber,
          showSerialBadge: showSerialBadge,
        ),
      ];
    }
    if (compact) {
      return _denseA4LabelBody(
        data: data,
        size: size,
        symbol: symbol,
        showLastPurchase: showLastPurchase,
        hideFinancials: hideFinancials,
        showStockOnLabel: showStockOnLabel,
      );
    }
    final code = _symbologyValue(
      data,
      symbol: symbol,
      webBase: AppConfig.webAppBaseUrl,
    );
    final codeLine = pdfLabelText(
      data.itemCode.trim().isEmpty ? code : data.itemCode.trim(),
    );
    final (titleSize, codeSize, bcHeight, qrSize) = _sizes(size);
    final titleSz = titleSize;
    final codeSz = codeSize;
    final bcH = bcHeight;
    final safeName = pdfLabelText(
      sanitizePrintPayload(data.itemName, forQr: symbol == BarcodeSymbolMode.qrCode),
    );

    final children = <pw.Widget>[
      pw.Text(
        safeName,
        maxLines: 2,
        style: pw.TextStyle(fontSize: titleSz, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
    ];

    children.add(
      _safeBarcodeWidget(
        qr: symbol == BarcodeSymbolMode.qrCode,
        data: code,
        height: symbol == BarcodeSymbolMode.qrCode
            ? (qrSize > 0 ? qrSize : bcHeight)
            : bcH,
        width: qrSize > 0 ? qrSize : bcH,
      ),
    );
    children.add(pw.Text(codeLine, style: pw.TextStyle(fontSize: codeSz)));
    if (data.barcode != null &&
        data.barcode!.trim().isNotEmpty &&
        data.barcode!.trim() != codeLine) {
      children.add(
        pw.Text(
          pdfLabelText('BC ${data.barcode!.trim()}'),
          style: pw.TextStyle(fontSize: codeSz - 1),
        ),
      );
    }

    final stockDisplay = pdfQtyDisplayString(data.currentStock);

    if (qrSize > 0 && symbol == BarcodeSymbolMode.code128WithQr) {
      children.addAll([
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: code,
              width: qrSize,
              height: qrSize,
            ),
            if (showStockOnLabel && stockDisplay != null && size == LabelSize.large)
              pw.Text(
                pdfLabelText('Stock: $stockDisplay ${data.unit ?? ''}'),
                style: pw.TextStyle(fontSize: codeSize - 1),
              ),
          ],
        ),
      ]);
    }

    final stockStr = stockDisplay;
    if (showStockOnLabel && stockStr != null) {
      final u = pdfLabelText((data.unit ?? '').trim());
      children.add(pw.SizedBox(height: 2));
      children.add(
        pw.Text(
          pdfLabelText('Stock: $stockStr${u.isEmpty ? '' : ' $u'}'),
          style: pw.TextStyle(
            fontSize: codeSize - 1,
            fontWeight: pw.FontWeight.bold,
          ),
          maxLines: 1,
        ),
      );
    }

    final lastLine = _lastPurchaseLine(
      data,
      showLastPurchase: showLastPurchase,
      size: size,
      hideFinancials: hideFinancials,
      compact: size != LabelSize.large,
    );
    if (lastLine != null) {
      children.add(pw.SizedBox(height: 1));
      children.add(
        pw.Text(
          pdfLabelText(lastLine),
          style: pw.TextStyle(fontSize: codeSize - 1.5),
          maxLines: 2,
        ),
      );
    }

    final bags = _bagsLine(data);
    if (bags != null && size != LabelSize.small) {
      children.add(
        pw.Text(
          pdfLabelText(bags),
          style: pw.TextStyle(fontSize: codeSize - 1.5),
        ),
      );
    }

    return children;
  }

  /// A4 dense grid: name, larger barcode, one optional footer line (item code in cell header).
  static List<pw.Widget> _denseA4LabelBody({
    required BarcodeLabelData data,
    required LabelSize size,
    required BarcodeSymbolMode symbol,
    required bool showLastPurchase,
    required bool hideFinancials,
    required bool showStockOnLabel,
  }) {
    final code = _symbologyValue(
      data,
      symbol: symbol,
      webBase: AppConfig.webAppBaseUrl,
    );
    final (_, codeSize, bcHeight, qrSize) = _sizes(size);
    final titleSz = math.min(_sizes(size).$1, 7.5);
    final bcH = math.max(20.0, math.min(bcHeight, 24.0));
    final safeName = pdfLabelText(
      sanitizePrintPayload(data.itemName, forQr: symbol == BarcodeSymbolMode.qrCode),
    );

    final children = <pw.Widget>[
      pw.Text(
        safeName,
        maxLines: 2,
        style: pw.TextStyle(fontSize: titleSz, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      _safeBarcodeWidget(
        qr: symbol == BarcodeSymbolMode.qrCode,
        data: code,
        height: symbol == BarcodeSymbolMode.qrCode
            ? math.max(22.0, qrSize)
            : bcH,
        width: symbol == BarcodeSymbolMode.qrCode
            ? math.max(22.0, qrSize)
            : bcH * 2.4,
      ),
    ];

    final footer = _denseA4FooterLine(
      data,
      showStockOnLabel: showStockOnLabel,
      showLastPurchase: showLastPurchase,
      hideFinancials: hideFinancials,
      size: size,
    );
    if (footer != null) {
      children.addAll([
        pw.SizedBox(height: 2),
        pw.Text(
          footer,
          style: pw.TextStyle(
            fontSize: codeSize - 1,
            fontWeight: pw.FontWeight.bold,
          ),
          maxLines: 2,
        ),
      ]);
    }

    return children;
  }

  static String? _denseA4FooterLine(
    BarcodeLabelData data, {
    required bool showStockOnLabel,
    required bool showLastPurchase,
    required bool hideFinancials,
    required LabelSize size,
  }) {
    final stockDisplay = pdfQtyDisplayString(data.currentStock);
    final u = pdfLabelText((data.unit ?? '').trim());
    String? stockLine;
    if (showStockOnLabel && stockDisplay != null) {
      stockLine = pdfLabelText(
        'Stock: $stockDisplay${u.isEmpty ? '' : ' $u'}',
      );
    }
    final purchaseLine = _lastPurchaseLine(
      data,
      showLastPurchase: showLastPurchase,
      size: size,
      hideFinancials: hideFinancials,
      compact: true,
      omitEmptyPlaceholder: true,
    );
    if (stockLine != null && purchaseLine != null) {
      return pdfLabelText('$stockLine | $purchaseLine');
    }
    return stockLine ?? purchaseLine;
  }

  /// Thermal small: barcode left; name + date + qty right — no price, no unit text.
  static pw.Widget _smallThermalLabelRow({
    required BarcodeLabelData data,
    required BarcodeSymbolMode symbol,
    required bool showLastPurchase,
    bool compact = false,
    int? serialNumber,
    bool showSerialBadge = true,
  }) {
    final code = _symbologyValue(
      data,
      symbol: symbol,
      webBase: AppConfig.webAppBaseUrl,
    );
    final codeLine = data.itemCode.trim().isEmpty ? code : data.itemCode.trim();
    final bcH = compact ? 18.0 : 22.0;
    final nameSize = compact ? 6.0 : 7.0;
    final metaSize = compact ? 5.5 : 6.0;
    final safeName = pdfLabelText(
      sanitizePrintPayload(data.itemName, forQr: symbol == BarcodeSymbolMode.qrCode),
    );

    final qtyStr = pdfQtyDisplayString(data.lastPurchaseQty);
    String? dateStr;
    if (showLastPurchase && data.lastPurchaseDate != null) {
      final d = data.lastPurchaseDate!;
      dateStr =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
    }

    final row = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          flex: compact ? 2 : 3,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              _safeBarcodeWidget(
                qr: symbol == BarcodeSymbolMode.qrCode,
                data: code,
                height: bcH,
                width: compact ? bcH : bcH * 1.6,
              ),
              if (!compact)
                pw.Text(
                  pdfLabelText(
                    codeLine.length > 18
                        ? '${codeLine.substring(0, 18)}...'
                        : codeLine,
                  ),
                  style: pw.TextStyle(fontSize: metaSize - 0.5),
                  maxLines: 1,
                ),
            ],
          ),
        ),
        pw.SizedBox(width: compact ? 1 : 2),
        pw.Expanded(
          flex: compact ? 3 : 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                safeName,
                maxLines: compact ? 1 : 2,
                style: pw.TextStyle(
                  fontSize: nameSize,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (dateStr != null)
                pw.Text(dateStr, style: pw.TextStyle(fontSize: metaSize)),
              if (qtyStr != null)
                pw.Text(
                  'Qty: $qtyStr',
                  style: pw.TextStyle(
                    fontSize: metaSize + (compact ? 0 : 1),
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (serialNumber != null && showSerialBadge) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              'SL $serialNumber',
              style: pw.TextStyle(
                fontSize: compact ? 5 : 6,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 1),
          row,
        ],
      );
    }
    return row;
  }

  /// Last purchase footer for PDF labels (ASCII-safe for default fonts).
  @visibleForTesting
  static String? lastPurchaseLineForLabel(
    BarcodeLabelData data, {
    required bool showLastPurchase,
    required LabelSize size,
    bool hideFinancials = false,
    bool compact = false,
    bool omitEmptyPlaceholder = false,
  }) =>
      _lastPurchaseLine(
        data,
        showLastPurchase: showLastPurchase,
        size: size,
        hideFinancials: hideFinancials,
        compact: compact,
        omitEmptyPlaceholder: omitEmptyPlaceholder,
      );

  static String? _lastPurchaseLine(
    BarcodeLabelData data, {
    required bool showLastPurchase,
    required LabelSize size,
    bool hideFinancials = false,
    bool compact = false,
    bool omitEmptyPlaceholder = false,
  }) {
    if (!showLastPurchase) return null;
    if (size == LabelSize.small && !compact) return null;
    final parts = <String>[];
    if (data.lastPurchaseDate != null) {
      final d = data.lastPurchaseDate!;
      final ds =
          '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year % 100}';
      parts.add(ds);
    }
    final qtyStr = pdfQtyDisplayString(data.lastPurchaseQty);
    if (qtyStr != null) {
      final u = pdfLabelText((data.lastPurchaseUnit ?? data.unit ?? '').trim());
      parts.add('$qtyStr${u.isEmpty ? '' : ' $u'}');
    }
    final rate = BarcodeLabelData.finiteQty(data.lastPurchaseRate);
    if (!hideFinancials && rate != null && rate > 0) {
      parts.add('Rs.${rate.toStringAsFixed(0)}');
    }
    final sup = data.supplierName?.trim() ?? '';
    if (sup.isNotEmpty && !compact) {
      final short = sup.length > 18 ? '${sup.substring(0, 18)}...' : sup;
      parts.add(pdfLabelText(short));
    }
    if (parts.isEmpty) {
      return omitEmptyPlaceholder ? null : 'No purchase yet';
    }
    return pdfLabelText(parts.join(pdfInlineSep));
  }

  static String? _bagsLine(BarcodeLabelData data) {
    final n = pdfQtyDisplayString(data.lastPurchaseQty);
    if (n == null) return null;
    final u = (data.lastPurchaseUnit ?? data.unit ?? '').toLowerCase();
    if (u.contains('bag') || u == 'sack') {
      return 'Bags: $n';
    }
    return null;
  }

  static double _finiteDim(double v, {double fallback = 20, double max = 120}) {
    if (!v.isFinite || v <= 0) return fallback;
    return v.clamp(6, max);
  }

  static pw.Widget _safeBarcodeWidget({
    required bool qr,
    required String data,
    required double height,
    required double width,
  }) {
    final payload = sanitizePrintPayload(data, forQr: qr);
    final h = _finiteDim(height, fallback: 18, max: 80);
    final w = _finiteDim(width, fallback: h, max: 80);
    try {
      if (qr) {
        return pw.BarcodeWidget(
          barcode: Barcode.qrCode(),
          data: payload,
          width: w,
          height: h,
        );
      }
      return pw.BarcodeWidget(
        barcode: Barcode.code128(),
        data: payload,
        drawText: false,
        height: h,
      );
    } catch (_) {
      return pw.Text(
        payload,
        style: pw.TextStyle(fontSize: math.min(6, h)),
        maxLines: 2,
      );
    }
  }

  static String _month(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m - 1];
  }
}

/// Top-level for [Isolate.run] (must be a library function).
Future<Uint8List> _barcodeA4DenseFromPayload(Map<String, dynamic> payload) {
  return BarcodePdfService.buildA4DenseGridPdf(payload);
}
