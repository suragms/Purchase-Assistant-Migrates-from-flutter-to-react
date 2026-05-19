import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum LabelSize { small, medium, large }

class BarcodeLabelData {
  const BarcodeLabelData({
    required this.itemCode,
    required this.itemName,
    this.unit,
    this.currentStock,
    this.lastPurchaseDate,
    this.lastPurchaseQty,
    this.lastPurchaseUnit,
    this.lastPurchaseRate,
  });

  final String itemCode;
  final String itemName;
  final String? unit;
  final double? currentStock;
  final DateTime? lastPurchaseDate;
  final double? lastPurchaseQty;
  final String? lastPurchaseUnit;
  final double? lastPurchaseRate;

  static BarcodeLabelData? fromApiMap(Map<String, dynamic> j) {
    final code = j['item_code']?.toString() ?? '';
    if (code.isEmpty) return null;
    DateTime? lpDate;
    final lpRaw = j['last_purchase_date'];
    if (lpRaw is String && lpRaw.isNotEmpty) {
      lpDate = DateTime.tryParse(lpRaw);
    }
    return BarcodeLabelData(
      itemCode: code,
      itemName: j['item_name']?.toString() ?? code,
      unit: j['unit']?.toString(),
      currentStock: (j['current_stock'] as num?)?.toDouble(),
      lastPurchaseDate: lpDate,
      lastPurchaseQty: (j['last_purchase_qty'] as num?)?.toDouble(),
      lastPurchaseUnit: j['last_purchase_unit']?.toString(),
      lastPurchaseRate: (j['last_purchase_rate'] as num?)?.toDouble(),
    );
  }
}

class BarcodePdfService {
  static Future<Uint8List> generateSingleLabel({
    required BarcodeLabelData data,
    LabelSize size = LabelSize.medium,
    int copies = 1,
    bool showLastPurchase = true,
  }) async {
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
    int labelsPerRow = 1,
  }) async {
    final expanded = <BarcodeLabelData>[];
    for (final data in items) {
      for (var c = 0; c < copiesPerItem; c++) {
        expanded.add(data);
      }
    }
    if (expanded.isEmpty) {
      return pw.Document().save();
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

  static PdfPageFormat _pageFormat(LabelSize size) => switch (size) {
        LabelSize.small =>
          const PdfPageFormat(38 * PdfPageFormat.mm, 19 * PdfPageFormat.mm),
        LabelSize.large =>
          const PdfPageFormat(100 * PdfPageFormat.mm, 50 * PdfPageFormat.mm),
        LabelSize.medium =>
          const PdfPageFormat(57 * PdfPageFormat.mm, 32 * PdfPageFormat.mm),
      };

  static (double titleSize, double codeSize, double bcHeight, double qrSize)
      _sizes(LabelSize size) => switch (size) {
            LabelSize.small => (7.0, 6.0, 28.0, 0.0),
            LabelSize.large => (10.0, 8.0, 40.0, 36.0),
            LabelSize.medium => (8.0, 7.0, 36.0, 28.0),
          };

  static List<pw.Widget> _labelBody({
    required BarcodeLabelData data,
    required LabelSize size,
    required bool showLastPurchase,
  }) {
    final code = data.itemCode.trim().isEmpty ? data.itemName : data.itemCode;
    final bc = Barcode.code128();
    final (titleSize, codeSize, bcHeight, qrSize) = _sizes(size);

    final children = <pw.Widget>[
      pw.Text(
        data.itemName,
        maxLines: 2,
        style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
      pw.BarcodeWidget(
        barcode: bc,
        data: code,
        drawText: false,
        height: bcHeight,
      ),
      pw.Text(code, style: pw.TextStyle(fontSize: codeSize)),
    ];

    if (qrSize > 0) {
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

    final lastLine = _lastPurchaseLine(data, showLastPurchase: showLastPurchase, size: size);
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
  }) {
    if (!showLastPurchase || size == LabelSize.small) return null;
    if (data.lastPurchaseDate == null) return 'No purchase yet';
    final d = data.lastPurchaseDate!;
    final ds =
        '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year % 100}';
    final qty = data.lastPurchaseQty;
    final qtyStr = qty == null
        ? ''
        : (qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(1));
    final u = data.lastPurchaseUnit ?? data.unit ?? '';
    final rate = data.lastPurchaseRate != null
        ? '₹${data.lastPurchaseRate!.toStringAsFixed(0)}'
        : '';
    return 'Last: $ds  $qtyStr $u  $rate'.trim();
  }

  static String? _bagsLine(BarcodeLabelData data) {
    final qty = data.lastPurchaseQty;
    if (qty == null || qty <= 0) return null;
    final u = (data.lastPurchaseUnit ?? data.unit ?? '').toLowerCase();
    if (u.contains('bag') || u == 'sack') {
      final n = qty == qty.roundToDouble() ? '${qty.round()}' : qty.toStringAsFixed(1);
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
