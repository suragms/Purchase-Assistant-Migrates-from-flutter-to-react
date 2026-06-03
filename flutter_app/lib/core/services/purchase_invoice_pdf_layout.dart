// Professional A4 purchase invoice: black text, light grey grid (see plan).

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../calc_engine.dart';
import '../models/business_profile.dart';
import '../models/trade_purchase_models.dart';
import '../utils/trade_purchase_commission.dart';
import '../utils/trade_purchase_rate_display.dart';
import 'purchase_invoice_amount_words.dart';
import 'pdf_text_safe.dart';
import '../utils/unit_utils.dart';

final _num2 = NumberFormat('#,##,##0.00', 'en_IN');
final _num0 = NumberFormat('#,##,##0.##', 'en_IN');
final _dateFmt = DateFormat('dd MMM yyyy');
final _dateTimeFmt = DateFormat('dd MMM yyyy, hh:mm a');

const _border = PdfColor.fromInt(0xFFCBD5E1);
const _muted = PdfColor.fromInt(0xFF64748B);

String _rsPdf(num n) => 'Rs. ${_num2.format(n)}';
String _empty(String? s) {
  final t = s?.trim();
  if (t == null || t.isEmpty) return pdfEmpty;
  return safePdfText(t);
}

/// Maps API line to calc line (mirrors [purchase_draft] `_lineToCalc` semantics).
TradeCalcLine _purchaseLineToCalc(TradePurchaseLine l) {
  return TradeCalcLine(
    qty: l.qty,
    landingCost: l.landingCost,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    discountPercent: l.discount,
    taxPercent: l.taxPercent,
    freightType: l.freightType,
    freightValue: l.freightValue,
    deliveredRate: l.deliveredRate,
    billtyRate: l.billtyRate,
  );
}

TradeCommissionLine _purchaseLineToCommissionBasis(TradePurchaseLine l) {
  return TradeCommissionLine(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    kgPerUnit: l.kgPerUnit,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
}

TradeCalcRequest _purchaseToCalcRequest(TradePurchase p) {
  return TradeCalcRequest(
    lines: [for (final l in p.lines) _purchaseLineToCalc(l)],
    headerDiscountPercent: p.discount,
    commissionPercent: p.commissionPercent,
    commissionMode: p.commissionMode,
    commissionMoney: p.commissionMoney,
    commissionBasisLines: [for (final l in p.lines) _purchaseLineToCommissionBasis(l)],
    freightAmount: p.freightAmount,
    freightType: p.freightType ?? 'separate',
    billtyRate: p.billtyRate,
    deliveredRate: p.deliveredRate,
  );
}

bool _purchaseLinesHaveItemLevelCharges(TradePurchase p) {
  for (final l in p.lines) {
    if (l.freightValue != null ||
        l.deliveredRate != null ||
        l.billtyRate != null) {
      return true;
    }
  }
  return false;
}

double _lineRollupMoney(TradePurchaseLine l) {
  final c = _purchaseLineToCalc(l);
  return l.lineTotal ?? (lineMoney(c) + lineItemFreightCharges(c));
}

pw.Widget _tCell(
  String text, {
  double fs = 7.0,
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
  PdfColor color = PdfColors.black,
  int? maxLines,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    child: pw.Text(
      text,
      textAlign: align,
      maxLines: maxLines,
      style: pw.TextStyle(
        fontSize: fs,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

pw.Widget _invoiceHeader({
  required BusinessProfile biz,
  required TradePurchase p,
  pw.ImageProvider? logo,
}) {
  final title = safePdfText(
    biz.displayTitle.trim().isNotEmpty ? biz.displayTitle : 'Business',
  );
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: _border, width: 1),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 8),
            child: pw.Image(logo, width: 40, height: 40, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                safePdfText(kPurchaseOrderPdfTitle),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              if (biz.displayTitle.trim().isNotEmpty)
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              if (biz.address != null && biz.address!.trim().isNotEmpty)
                pw.Text(
                  safePdfText(biz.address!),
                  style: const pw.TextStyle(fontSize: 9, color: _muted, height: 1.3),
                ),
              pw.Text(
                'Phone: ${_empty(biz.phone)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
              ),
              if (biz.gstNumber != null && biz.gstNumber!.trim().isNotEmpty)
                pw.Text('GSTIN: ${biz.gstNumber}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
              if (biz.contactEmail != null && biz.contactEmail!.trim().isNotEmpty)
                pw.Text('Email: ${biz.contactEmail}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
            ],
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Order',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              pw.SizedBox(height: 4),
              pw.Text('No. ${_empty(p.humanId)}',
                  style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.black)),
              if (p.invoiceNumber != null && p.invoiceNumber!.trim().isNotEmpty)
                pw.Text('Bill / ref: ${p.invoiceNumber}',
                    style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              pw.Text('Date: ${_dateTimeFmt.format(p.purchaseDate)}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
              if (p.paymentDays != null)
                pw.Text('Payment days: ${p.paymentDays}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
              if (p.dueDate != null)
                pw.Text('Due: ${_dateFmt.format(p.dueDate!)}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.black)),
              pw.SizedBox(height: 2),
              pw.Text('Status: ${p.statusEnum.label}',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

String? _brokerCommissionBrokerBlockLine(TradePurchase p) {
  if (tradePurchaseCommissionInr(p) <= 1e-9) return null;
  final mode = p.commissionMode.trim().toLowerCase();
  if (mode == 'percent' && p.commissionPercent != null) {
    final c = p.commissionPercent!;
    return 'Commission: ${c == c.roundToDouble() ? c.round().toString() : c.toStringAsFixed(1)}%';
  }
  final cm = p.commissionMoney;
  if (cm == null) return 'Commission: (see totals)';
  return switch (mode) {
    'flat_invoice' => 'Commission: ${_rsPdf(cm)} (once on bill)',
    'flat_kg' => 'Commission: ${_rsPdf(cm)} / kg',
    'flat_bag' => 'Commission: ${_rsPdf(cm)} / bag',
    'flat_box' => 'Commission: ${_rsPdf(cm)} / box',
    'flat_tin' => 'Commission: ${_rsPdf(cm)} / tin',
    _ => 'Commission: (see totals)',
  };
}

pw.Widget _supplierBrokerBlock(TradePurchase p) {
  final commLine = _brokerCommissionBrokerBlockLine(p);
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.5),
    columnWidths: {
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(1),
    },
    children: [
      pw.TableRow(
        children: [
          _tCell('Supplier', bold: true, fs: 8.5),
          _tCell('Broker', bold: true, fs: 8.5),
        ],
      ),
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_empty(p.supplierName),
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.Text('Phone: ${_empty(p.supplierPhone)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.black)),
                if (p.supplierAddress != null && p.supplierAddress!.trim().isNotEmpty)
                  pw.Text(
                    safePdfText(p.supplierAddress!.trim()),
                    style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2),
                  ),
                pw.Text('GSTIN: ${_empty(p.supplierGst)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.black)),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_empty(p.brokerName),
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.Text('Phone: ${_empty(p.brokerPhone)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.black)),
                if (commLine != null)
                  pw.Text(commLine,
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.black)),
                if (p.brokerLocation != null && p.brokerLocation!.trim().isNotEmpty)
                  pw.Text(
                    safePdfText(p.brokerLocation!.trim()),
                    style: const pw.TextStyle(fontSize: 8, color: _muted, height: 1.2),
                  ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

String _pdfPurchaseRateStr(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplayPurchaseRate(l);
  return '${_rsPdf(r)}/${ledgerPurchaseRateDisplayDim(l)}';
}

String _pdfSellingRateStr(TradePurchaseLine l) {
  final r = tradePurchaseLineDisplaySellingRate(l);
  if (r == null) return pdfEmpty;
  return '${_rsPdf(r)}/${ledgerSellingRateDisplayDim(l)}';
}

// (intentionally removed) kg column removed from the PDF items table.

pw.Widget _lineItemsTable(TradePurchase p) {
  // Master rebuild PDF spec:
  // Item | Qty | Unit | P Rate | S Rate | Total
  final col = <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(2.8), // Item
    1: const pw.FixedColumnWidth(34), // Qty
    2: const pw.FixedColumnWidth(28), // Unit
    3: const pw.FixedColumnWidth(54), // P Rate
    4: const pw.FixedColumnWidth(54), // S Rate
    5: const pw.FixedColumnWidth(46), // Total
  };
  final header = pw.TableRow(
    children: [
      _tCell('Item', bold: true, fs: 6.4),
      _tCell('Qty', bold: true, align: pw.TextAlign.right, fs: 6.4),
      _tCell('Unit', bold: true, align: pw.TextAlign.center, fs: 6.4),
      _tCell('P Rate', bold: true, align: pw.TextAlign.right, fs: 6.4),
      _tCell('S Rate', bold: true, align: pw.TextAlign.right, fs: 6.4),
      _tCell('Total', bold: true, align: pw.TextAlign.right, fs: 6.4),
    ],
  );
  final rows = <pw.TableRow>[header];
  for (var i = 0; i < p.lines.length; i++) {
    final l = p.lines[i];
    rows.add(
      pw.TableRow(
        children: [
          _tCell(safePdfText(l.itemName), fs: 6.2, maxLines: 3),
          _tCell(formatStockQtyForUnit(l.unit, l.qty.toDouble()), align: pw.TextAlign.right, fs: 6.2),
          _tCell(safePdfText(l.unit.trim()), align: pw.TextAlign.center, fs: 6.2),
          _tCell(_pdfPurchaseRateStr(l), align: pw.TextAlign.right, fs: 5.9),
          _tCell(_pdfSellingRateStr(l), align: pw.TextAlign.right, fs: 5.9),
          _tCell(
            _rsPdf(_lineRollupMoney(l)),
            align: pw.TextAlign.right,
            fs: 6.1,
          ),
        ],
      ),
    );
  }
  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.4),
    columnWidths: col,
    children: rows,
  );
}

String _brokerCommissionPdfLabel(TradePurchase p) {
  final mode = p.commissionMode.trim().toLowerCase();
  if (mode == 'percent' && p.commissionPercent != null) {
    return 'Broker commission (${_num0.format(p.commissionPercent!)}%)';
  }
  return switch (mode) {
    'flat_invoice' => 'Broker commission (fixed, bill)',
    'flat_kg' => 'Broker commission (per kg × total kg)',
    'flat_bag' => 'Broker commission (per bag × qty)',
    'flat_box' => 'Broker commission (per box × qty)',
    'flat_tin' => 'Broker commission (per tin × qty)',
    _ => 'Broker commission',
  };
}

class _SummaryNumbers {
  _SummaryNumbers({
    required this.sumLineMoney,
    required this.sumTaxable,
    required this.sumLineTax,
    required this.headerDiscountAmount,
    required this.afterHeader,
    required this.freight,
    required this.commission,
  });

  final double sumLineMoney;
  final double sumTaxable;
  final double sumLineTax;
  final double headerDiscountAmount;
  final double afterHeader;
  final double freight;
  final double commission;
}

_SummaryNumbers _computeSummaryBreakdown(TradePurchase p) {
  var sumLineMoney = 0.0;
  var sumTaxable = 0.0;
  var sumLineTax = 0.0;
  final lineCharges = _purchaseLinesHaveItemLevelCharges(p);
  for (final l in p.lines) {
    final c = _purchaseLineToCalc(l);
    sumLineMoney += _lineRollupMoney(l);
    sumTaxable += lineTaxableAfterLineDisc(c);
    sumLineTax += lineTaxAmount(c);
  }
  final hd = p.discount ?? 0.0;
  final hdf = hd > 100 ? 100.0 : hd;
  final afterHeader = sumLineMoney * (1.0 - hdf / 100.0);
  final headerDiscountAmount = sumLineMoney - afterHeader;
  var freight = lineCharges ? 0.0 : (p.freightAmount ?? 0.0);
  if (p.freightType == 'included') freight = 0.0;
  final commission = tradePurchaseCommissionInr(p);
  return _SummaryNumbers(
    sumLineMoney: sumLineMoney,
    sumTaxable: sumTaxable,
    sumLineTax: sumLineTax,
    headerDiscountAmount: headerDiscountAmount,
    afterHeader: afterHeader,
    freight: freight,
    commission: commission,
  );
}

pw.Widget _summaryBlock(TradePurchase p, _SummaryNumbers s, {required bool totalMatches}) {
  pw.Widget row(String label, String value, {bool bold = false, double h = 1.0}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 200,
            child: pw.Text(
              label,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: bold ? 10 : 8.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: bold ? 11 : 8.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  final lineCharges = _purchaseLinesHaveItemLevelCharges(p);
  final bill = lineCharges ? 0.0 : (p.billtyRate ?? 0.0);
  final del = lineCharges ? 0.0 : (p.deliveredRate ?? 0.0);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      row('Subtotal (incl. line tax)', _rsPdf(s.sumLineMoney)),
      if (s.headerDiscountAmount > 0.001)
        row('Header discount', '- ${_rsPdf(s.headerDiscountAmount)}'),
      row('Net after discount', _rsPdf(s.afterHeader)),
      if (s.freight > 0) row('Freight', _rsPdf(s.freight)),
      if (s.commission > 0)
        row(_brokerCommissionPdfLabel(p), _rsPdf(s.commission)),
      if (del > 0) row('Delivered / other', _rsPdf(del)),
      if (bill > 0) row('Billty / charges', _rsPdf(bill)),
      pw.SizedBox(height: 4),
      row('FINAL TOTAL', _rsPdf(p.totalAmount), bold: true),
      if (!totalMatches)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            'Note: Recomputed total does not match stored total; FINAL TOTAL is the server value.',
            style: const pw.TextStyle(fontSize: 6.5, color: _muted),
            textAlign: pw.TextAlign.right,
          ),
        ),
    ],
  );
}

String? _purchasePdfTotalsWeightFooterLine(TradePurchase p) {
  var kg = 0.0;
  var bags = 0.0;
  var boxes = 0.0;
  var tins = 0.0;
  for (final l in p.lines) {
    kg += ledgerTradeLineWeightKg(
      itemName: l.itemName,
      unit: l.unit,
      qty: l.qty,
      catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
      catalogDefaultKgPerBag: l.defaultKgPerBag,
      kgPerUnit: l.kgPerUnit,
      boxMode: l.boxMode,
      itemsPerBox: l.itemsPerBox,
      weightPerItem: l.weightPerItem,
      kgPerBox: l.kgPerBox,
      weightPerTin: l.weightPerTin,
    );
    final u = l.unit.trim().toLowerCase();
    if (u == 'bag' || u == 'sack') {
      bags += l.qty;
    } else if (u == 'box') {
      boxes += l.qty;
    } else if (u == 'tin') {
      tins += l.qty;
    }
  }
  final parts = <String>[];
  if (bags > 1e-6) {
    parts.add(
      '${bags == bags.roundToDouble() ? bags.round() : bags} ${bags == 1 ? 'bag' : 'bags'}',
    );
  }
  if (boxes > 1e-6) {
    parts.add(
      '${boxes == boxes.roundToDouble() ? boxes.round() : boxes} ${boxes == 1 ? 'box' : 'boxes'}',
    );
  }
  if (tins > 1e-6) {
    parts.add(
      '${tins == tins.roundToDouble() ? tins.round() : tins} ${tins == 1 ? 'tin' : 'tins'}',
    );
  }
  if (kg > 1e-6) {
    parts.add('${_num0.format(kg)} kg');
  }
  if (parts.isEmpty) return null;
  return safePdfText('Total: ${parts.join(pdfInlineSep)}');
}

pw.Widget _footerBlock(
  BusinessProfile biz,
  TradePurchase p, {
  String? generatedByName,
}) {
  final wLine = _purchasePdfTotalsWeightFooterLine(p);
  final generatedAt = _dateTimeFmt.format(DateTime.now());
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(height: 0.5, color: _border),
      pw.SizedBox(height: 4),
      pw.Text(
        'Generated: $generatedAt',
        style: const pw.TextStyle(fontSize: 7.5, color: _muted),
      ),
      if (generatedByName != null && generatedByName.trim().isNotEmpty)
        pw.Text(
          'Created by: ${safePdfText(generatedByName.trim())}',
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      pw.Text(
        'Amount in words: ${amountInWordsInr(p.totalAmount)}',
        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black, height: 1.25),
      ),
      if (wLine != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          wLine,
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black, height: 1.2),
        ),
      ],
      if (p.invoiceNumber != null && p.invoiceNumber!.trim().isNotEmpty)
        pw.Text(
          'Reference: ${p.invoiceNumber}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Received / verified',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.SizedBox(height: 20),
              pw.Container(
                width: 120,
                height: 0.5,
                color: _border,
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('For ${biz.displayTitle.isNotEmpty ? biz.displayTitle : "Business"}',
                  style: pw.TextStyle(
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              pw.SizedBox(height: 20),
              pw.Text('Authorised signatory', style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.SizedBox(height: 4),
              pw.Text('(stamp)', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ],
          ),
        ],
      ),
    ],
  );
}

/// A4, ~10mm margins, print-ready professional purchase order.
Future<pw.Document> buildProfessionalPurchaseInvoiceDoc({
  required TradePurchase purchase,
  required BusinessProfile business,
  pw.ImageProvider? logo,
  pw.ThemeData? pdfTheme,
  String? generatedByName,
}) async {
  final doc = pw.Document(theme: pdfTheme);
  final req = _purchaseToCalcRequest(purchase);
  final totals = computeTradeTotals(req);
  final summary = _computeSummaryBreakdown(purchase);
  final diff1 = (totals.amountSum - purchase.totalAmount).abs();
  final showMismatch = diff1 > 0.02;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pdfTheme,
      build: (ctx) => [
        _invoiceHeader(biz: business, p: purchase, logo: logo),
        pw.SizedBox(height: 8),
        _supplierBrokerBlock(purchase),
        pw.SizedBox(height: 8),
        _lineItemsTable(purchase),
        pw.SizedBox(height: 8),
        _summaryBlock(
          purchase,
          summary,
          totalMatches: !showMismatch,
        ),
        pw.SizedBox(height: 8),
        _footerBlock(business, purchase, generatedByName: generatedByName),
      ],
    ),
  );
  return doc;
}

/// Commission line for the simple [buildPurchaseReceiptDoc] (same math as full invoice).
double purchaseBrokerCommissionForReceipt(TradePurchase p) =>
    _computeSummaryBreakdown(p).commission;

/// Same line mapping as the invoice (for tests / receipt).
TradeCalcLine tradePurchaseLineToCalcLine(TradePurchaseLine l) =>
    _purchaseLineToCalc(l);

/// Same request as the full invoice PDF (for parity tests).
TradeCalcRequest tradeCalcRequestFromTradePurchase(TradePurchase p) =>
    _purchaseToCalcRequest(p);
