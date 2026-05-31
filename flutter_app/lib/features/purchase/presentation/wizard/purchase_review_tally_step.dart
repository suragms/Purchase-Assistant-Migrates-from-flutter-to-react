import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/calc_engine.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/utils/trade_purchase_rate_display.dart';
import '../../domain/purchase_draft.dart';
import '../../mapping/purchase_line_display_adapter.dart';
import '../../state/purchase_draft_provider.dart';
import '../../state/purchase_trade_preview_provider.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

TradeCalcLine _lineToCalc(PurchaseLineDraft l) {
  return TradeCalcLine(
    qty: l.qty,
    landingCost: l.landingCost,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    taxPercent: l.taxPercent,
    discountPercent: l.lineDiscountPercent,
    freightType: l.freightType,
    freightValue: l.freightValue,
    deliveredRate: l.deliveredRate,
    billtyRate: l.billtyRate,
  );
}

double _lineBuyApprox(PurchaseLineDraft l) {
  final kpu = l.kgPerUnit;
  final pk = l.landingCostPerKg;
  if (kpu != null && pk != null && kpu > 0 && pk > 0) {
    return l.qty * kpu * pk;
  }
  return l.qty * l.landingCost;
}

String _pRateLine(PurchaseLineDraft l, Map<String, dynamic>? rateContext) {
  final tl = tradeLineForDisplay(l, rateContext: rateContext);
  final r = tradePurchaseLineDisplayPurchaseRate(tl);
  final suffix = unit_lbl.purchaseRateSuffix(tl);
  return '₹${r.toStringAsFixed(2)}/$suffix';
}

String _sRateLine(PurchaseLineDraft l, Map<String, dynamic>? rateContext) {
  final tl = tradeLineForDisplay(l, rateContext: rateContext);
  final r = tradePurchaseLineDisplaySellingRate(tl);
  if (r == null || r <= 0) return '—';
  final suffix = unit_lbl.sellingRateSuffix(tl);
  return '₹${r.toStringAsFixed(2)}/$suffix';
}

String _qtyHuman(PurchaseLineDraft l) {
  final u = l.unit.trim();
  final q = formatStockQtyForUnit(u, l.qty);
  if (l.kgPerUnit != null &&
      l.kgPerUnit! > 0 &&
      (u.toLowerCase() == 'bag' || u.toLowerCase() == 'sack')) {
    final kg = l.qty * l.kgPerUnit!;
    return '$q $u • ${formatStockQtyForUnit('kg', kg)} kg';
  }
  return '$q $u';
}

/// Step 4 — read-only Tally-style recap + expandable line math.
class PurchaseReviewTallyStep extends ConsumerWidget {
  const PurchaseReviewTallyStep({
    super.key,
    required this.isEdit,
    required this.previewHumanId,
    required this.editHumanId,
  });

  final bool isEdit;
  final String? previewHumanId;
  final String? editHumanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(purchaseDraftProvider);
    final bd = ref.watch(purchaseStrictBreakdownProvider);
    final qt = ref.watch(purchaseQuantityTotalsProvider);

    final supplier = draft.supplierName?.trim() ?? '—';
    final broker = draft.brokerName?.trim();
    final dateStr =
        DateFormat('dd MMM yyyy').format(draft.purchaseDate ?? DateTime.now());
    final purLabel =
        isEdit ? (editHumanId ?? '—') : (previewHumanId ?? 'New');

    var estRetail = 0.0;
    var hasRetail = false;
    for (final l in draft.lines) {
      final sp = l.sellingPrice;
      if (sp == null || sp <= 0) continue;
      estRetail += sp * l.qty - _lineBuyApprox(l);
      hasRetail = true;
    }

    final unitBits = <String>[];
    if (qt.totalKg > 1e-6) {
      unitBits.add('${formatStockQtyForUnit('kg', qt.totalKg)} KG');
    }
    qt.qtyByUnit.forEach((k, v) {
      if (v > 1e-9) {
        final lk = k.trim().toLowerCase();
        if (lk == 'kg' || lk == 'kgs' || lk == 'kilogram') {
          return;
        }
        unitBits.add(
            '${formatStockQtyForUnit(k, v.toDouble())} ${k.toUpperCase()}');
      }
    });
    final qtyLine = unitBits.isEmpty ? '—' : unitBits.join(' • ');

    final legacyOverrides = draft.lines.any((l) =>
        (l.deliveredRate != null && l.deliveredRate! > 1e-9) ||
        (l.billtyRate != null && l.billtyRate! > 1e-9) ||
        (l.freightValue != null && l.freightValue! > 1e-9) ||
        (l.lineDiscountPercent != null && l.lineDiscountPercent! > 1e-9));

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget termsSnapshot() {
      final pd = draft.paymentDays;
      final cm = draft.commissionMode;
      final cp = draft.commissionPercent;
      final cMoney = draft.commissionMoney;
      final fr = draft.freightAmount;
      final hd = draft.headerDiscountPercent;
      final dr = draft.deliveredRate;
      final br = draft.billtyRate;
      String? commissionLine() {
        if (cm == kPurchaseCommissionModePercent) {
          if (cp == null || cp <= 1e-9) return null;
          return 'Commission: ${cp.toStringAsFixed(2)}%';
        }
        if (cMoney == null || cMoney <= 1e-9) return null;
        return switch (cm) {
          kPurchaseCommissionModeFlatInvoice =>
            'Commission: ₹${cMoney.toStringAsFixed(2)} (once on bill)',
          kPurchaseCommissionModeFlatKg =>
            'Commission: ₹${cMoney.toStringAsFixed(2)} / kg × line kg',
          kPurchaseCommissionModeFlatBag =>
            'Commission: ₹${cMoney.toStringAsFixed(2)} / bag × line bags',
          kPurchaseCommissionModeFlatBox =>
            'Commission: ₹${cMoney.toStringAsFixed(2)} / box × line boxes',
          kPurchaseCommissionModeFlatTin =>
            'Commission: ₹${cMoney.toStringAsFixed(2)} / tin × line tins',
          _ => null,
        };
      }
      final lines = <String>[
        if (pd != null) 'Payment: $pd days',
        if (commissionLine() != null) commissionLine()!,
        if (draft.freightType == 'included')
          'Freight: included in rate'
        else if (fr != null && fr > 1e-9)
          'Freight: ${_inr(fr)}',
        if (hd != null && hd > 1e-9) 'Discount: ${hd.toStringAsFixed(2)}%',
        if (dr != null && dr > 1e-9)
          'Delivered rate: ₹${dr.toStringAsFixed(2)}',
        if (br != null && br > 1e-9) 'Billty rate: ₹${br.toStringAsFixed(2)}',
      ];
      if (lines.isEmpty) {
        return Text(
          'Terms: (none set)',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final s in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                s,
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              supplier,
              if (broker != null && broker.isNotEmpty) broker,
              dateStr,
              'PUR $purLabel',
            ].join(' · '),
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          if (legacyOverrides) ...[
            const SizedBox(height: 10),
            Material(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'Some lines carry older per-line charges or discounts. Expanded details show stored line values.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Material(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: HexaColors.brandBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ReviewStat(label: 'QTY', value: qtyLine),
                      const Spacer(),
                      _ReviewStat(
                        label: 'GRAND TOTAL',
                        value: _inr(bd.grand),
                        isPrimary: true,
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    children: [
                      _ReviewStat(
                        label: 'TAX TOTAL',
                        value: _inr(bd.taxTotal),
                      ),
                      const _ReviewMetricSep(),
                      _ReviewStat(
                        label: 'CHARGES',
                        value: _inr(bd.commission + bd.freight),
                      ),
                      const Spacer(),
                      if (hasRetail)
                        _ReviewStat(
                          label: 'EST. PROFIT',
                          value: _inr(estRetail),
                          isSuccess: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Items',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < draft.lines.length; i++)
            _ReviewLineTile(
              index: i + 1,
              lineIndex: i,
              line: draft.lines[i],
            ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          termsSnapshot(),
        ],
      ),
    );
  }
}

class _ReviewLineTile extends ConsumerWidget {
  const _ReviewLineTile({
    required this.index,
    required this.lineIndex,
    required this.line,
  });

  final int index;
  final int lineIndex;
  final PurchaseLineDraft line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final buy = _lineBuyApprox(line);
    final li = _lineToCalc(line);
    final g = lineGrossBase(li);
    final taxable = lineTaxableAfterLineDisc(li);
    final snap = ref.watch(tradePurchasePreviewProvider);
    final rateCtx = tradePreviewLineRateContext(snap, lineIndex);
    final serverLt = tradePreviewLineTotal(snap, lineIndex);
    final lineTotal = serverLt ?? lineMoney(li);
    final taxAmt = lineTotal - taxable;
    final discRupees = g - taxable;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$index. ${line.itemName}',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _qtyHuman(line),
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'P ${_pRateLine(line, rateCtx)}  ·  S ${_sRateLine(line, rateCtx)}',
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _inr(buy),
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          subtitle: const Text(
            'View details — line math',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Color(0xFF0D9488),
            ),
          ),
          children: [
            _detailRow('Purchase rate (display)', _pRateLine(line, rateCtx)),
            _detailRow('Selling rate (display)', _sRateLine(line, rateCtx)),
            _detailRow('Line gross (qty × purchase)', _inr(g)),
            if (discRupees > 1e-6)
              _detailRow(
                'After line discount',
                '− ${_inr(discRupees)}',
              ),
            if (taxAmt > 1e-6)
              _detailRow(
                'Tax on line',
                '+ ${_inr(taxAmt)}',
              ),
            if ((line.freightValue ?? 0) > 1e-9)
              _detailRow('Line freight', '+ ${_inr(line.freightValue!)}'),
            if ((line.deliveredRate ?? 0) > 1e-9)
              _detailRow('Line delivered', '+ ${_inr(line.deliveredRate!)}'),
            if ((line.billtyRate ?? 0) > 1e-9)
              _detailRow('Line billty', '+ ${_inr(line.billtyRate!)}'),
            const Divider(height: 16),
            _detailRow(
              'Line amount (engine)',
              _inr(lineTotal),
              emphasize: true,
            ),
            if (line.sellingPrice != null && line.sellingPrice! > 0) ...[
              const SizedBox(height: 6),
              _detailRow(
                'Est. line retail margin',
                _inr(line.sellingPrice! * line.qty - buy),
                valueColor: const Color(0xFF047857),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v, {bool emphasize = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: emphasize ? 14 : 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            v,
            style: TextStyle(
              fontSize: emphasize ? 15 : 13,
              fontWeight: FontWeight.w800,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStat extends StatelessWidget {
  const _ReviewStat({
    required this.label,
    required this.value,
    this.isPrimary = false,
    this.isSuccess = false,
  });

  final String label;
  final String value;
  final bool isPrimary;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final primaryColor = const Color(0xFF0F172A);
    final successColor = const Color(0xFF047857);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: tt.labelSmall?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 9,
            letterSpacing: 0.5,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: (isPrimary ? tt.titleLarge : tt.titleSmall)?.copyWith(
            fontWeight: FontWeight.w900,
            color: isSuccess ? successColor : primaryColor,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ReviewMetricSep extends StatelessWidget {
  const _ReviewMetricSep();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 24,
        width: 1,
        color: Colors.grey.shade300,
      ),
    );
  }
}
