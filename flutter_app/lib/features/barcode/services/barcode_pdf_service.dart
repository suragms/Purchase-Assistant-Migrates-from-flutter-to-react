import 'dart:isolate';
import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/json_coerce.dart';
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
    if (b.isNotEmpty) return b;
    return itemCode.trim();
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
      currentStock: coerceToDoubleNullable(j['currentStock']),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: coerceToDoubleNullable(j['lastPurchaseQty']),
      lastPurchaseUnit: j['lastPurchaseUnit'] as String?,
      lastPurchaseRate: coerceToDoubleNullable(j['lastPurchaseRate']),
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
      currentStock: coerceToDoubleNullable(j['current_stock']),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: coerceToDoubleNullable(j['last_purchase_qty']),
      lastPurchaseUnit: j['last_purchase_unit']?.toString(),
      lastPurchaseRate: coerceToDoubleNullable(j['last_purchase_rate']),
      supplierName: j['supplier_name']?.toString(),
    );
  }
}

class BarcodePdfService {
  static String _symbologyValue(BarcodeLabelData data) {
    final v = (data.barcode ?? data.itemCode).trim();
    if (v.isEmpty) {
      throw BarcodeOperationException(
        'Barcode image missing for "${data.itemName}".',
        kind: BarcodeOperationKind.barcodeRender,
      );
    }
    return v;
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
    LabelSize size = LabelSize.medium,
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
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> generateBatch({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.medium,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
    bool hideFinancials = false,
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
  static Future<Uint8List> generateBatchA4Dense({
    required List<BarcodeLabelData> items,
    LabelSize size = LabelSize.medium,
    int copiesPerItem = 1,
    bool showLastPurchase = true,
    bool hideFinancials = false,
    int columns = 4,
  }) async {
    final printable = _requirePrintable(items);
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
      'maxCols': columns.clamp(1, 6),
    };
    if (kIsWeb) {
      return _barcodeA4DenseFromPayload(payload);
    }
    return Isolate.run(() => _barcodeA4DenseFromPayload(payload));
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

    final mm = PdfPageFormat.mm;
    const margin = 5.0 * PdfPageFormat.mm;
    const gap = 2.0 * PdfPageFormat.mm;
    final (lwMm, lhMm) = a4DenseCellMm(size);
    final labelW = lwMm * mm;
    final labelH = lhMm * mm;
    const sheet = PdfPageFormat.a4;
    final innerW = sheet.width - 2 * margin;
    final innerH = sheet.height - 2 * margin;
    final maxCols = (payload['maxCols'] as int?) ?? 4;
    final cols = math.min(
      maxCols,
      math.max(1, ((innerW + gap) / (labelW + gap)).floor()),
    );
    final rows = math.max(1, ((innerH + gap) / (labelH + gap)).floor());
    final perPage = cols * rows;

    final doc = pw.Document();
    for (var base = 0; base < labels.length; base += perPage) {
      final chunk = labels.sublist(base, math.min(base + perPage, labels.length));
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
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: pw.Container(
                        width: labelW,
                        height: labelH,
                        padding: const pw.EdgeInsets.all(0.5),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.grey400,
                            width: 0.25,
                          ),
                        ),
                        child: pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          alignment: pw.Alignment.topCenter,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            mainAxisSize: pw.MainAxisSize.min,
                            children: _labelBody(
                              data: chunk[idx],
                              size: size,
                              showLastPurchase: showLastPurchase,
                              hideFinancials: hideFinancials,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  rowCells.add(
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: right, bottom: bottom),
                      child: pw.SizedBox(width: labelW, height: labelH),
                    ),
                  );
                }
              }
              pageRows.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: rowCells,
                ),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: pageRows,
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

  static List<pw.Widget> _labelBody({
    required BarcodeLabelData data,
    required LabelSize size,
    required bool showLastPurchase,
    bool hideFinancials = false,
    BarcodeSymbolMode symbol = BarcodeSymbolMode.code128WithQr,
  }) {
    final code = data.symbologyValue.isEmpty ? data.itemName : data.symbologyValue;
    final codeLine = data.itemCode.trim().isEmpty ? code : data.itemCode.trim();
    final (titleSize, codeSize, bcHeight, qrSize) = _sizes(size);

    final children = <pw.Widget>[
      pw.Text(
        data.itemName,
        maxLines: 2,
        style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
    ];

    if (symbol == BarcodeSymbolMode.qrCode) {
      final side = qrSize > 0 ? qrSize : bcHeight;
      children.add(
        pw.BarcodeWidget(
          barcode: Barcode.qrCode(),
          data: code,
          width: side,
          height: side,
        ),
      );
    } else {
      children.add(
        pw.BarcodeWidget(
          barcode: Barcode.code128(),
          data: code,
          drawText: false,
          height: bcHeight,
        ),
      );
    }
    children.add(pw.Text(codeLine, style: pw.TextStyle(fontSize: codeSize)));
    if (data.barcode != null &&
        data.barcode!.trim().isNotEmpty &&
        data.barcode!.trim() != codeLine) {
      children.add(
        pw.Text(
          'BC ${data.barcode!.trim()}',
          style: pw.TextStyle(fontSize: codeSize - 1),
        ),
      );
    }

    if (qrSize > 0 &&
        symbol == BarcodeSymbolMode.code128WithQr) {
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
            if (data.currentStock != null && size == LabelSize.large)
              pw.Text(
                'Stock: ${data.currentStock!.toStringAsFixed(0)} ${data.unit ?? ''}',
                style: pw.TextStyle(fontSize: codeSize - 1),
              ),
          ],
        ),
      ]);
    }

    final lastLine = _lastPurchaseLine(
      data,
      showLastPurchase: showLastPurchase,
      size: size,
      hideFinancials: hideFinancials,
    );
    if (lastLine != null) {
      children.add(pw.SizedBox(height: 2));
      children.add(
        pw.Text(lastLine, style: pw.TextStyle(fontSize: codeSize - 1)),
      );
    }

    final bags = _bagsLine(data);
    if (bags != null && size != LabelSize.small) {
      children.add(
        pw.Text(bags, style: pw.TextStyle(fontSize: codeSize - 1.5)),
      );
    }

    return children;
  }

  static String? _lastPurchaseLine(
    BarcodeLabelData data, {
    required bool showLastPurchase,
    required LabelSize size,
    bool hideFinancials = false,
  }) {
    if (!showLastPurchase || size == LabelSize.small) return null;
    final parts = <String>[];
    if (data.lastPurchaseDate != null) {
      final d = data.lastPurchaseDate!;
      final ds =
          '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year % 100}';
      parts.add(ds);
    }
    final qty = data.lastPurchaseQty;
    if (qty != null && qty > 0) {
      final rounded = qty.roundToDouble();
      final qtyStr = (qty - rounded).abs() < 0.001
          ? '${rounded.toInt()}'
          : qty.toStringAsFixed(1);
      final u = (data.lastPurchaseUnit ?? data.unit ?? '').trim();
      parts.add('$qtyStr${u.isEmpty ? '' : ' $u'}');
    }
    if (!hideFinancials &&
        data.lastPurchaseRate != null &&
        data.lastPurchaseRate! > 0) {
      parts.add('₹${data.lastPurchaseRate!.toStringAsFixed(0)}');
    }
    final sup = data.supplierName?.trim() ?? '';
    if (sup.isNotEmpty) {
      final short = sup.length > 18 ? '${sup.substring(0, 18)}…' : sup;
      parts.add(short);
    }
    if (parts.isEmpty) return 'No purchase yet';
    return parts.join(' · ');
  }

  static String? _bagsLine(BarcodeLabelData data) {
    final qty = data.lastPurchaseQty;
    if (qty == null || qty <= 0) return null;
    final u = (data.lastPurchaseUnit ?? data.unit ?? '').toLowerCase();
    if (u.contains('bag') || u == 'sack') {
      final rounded = qty.roundToDouble();
      final n = (qty - rounded).abs() < 0.001
          ? '${rounded.round()}'
          : qty.toStringAsFixed(1);
      return 'Bags: $n';
    }
    return null;
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
