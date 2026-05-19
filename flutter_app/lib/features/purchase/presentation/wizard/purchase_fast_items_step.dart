import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/strict_decimal.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../../core/utils/trade_purchase_rate_display.dart';
import '../../domain/purchase_draft.dart';
import '../../mapping/purchase_line_display_adapter.dart';
import '../../state/purchase_draft_provider.dart';
import '../../state/purchase_trade_preview_provider.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

typedef OpenAdvancedItemSheet = Future<void> Function({
  int? editIndex,
  Map<String, dynamic>? initialOverride,
});

/// Items step — expanded list + sticky [+ Add Item] (Part 2).
class PurchaseFastItemsStep extends ConsumerStatefulWidget {
  const PurchaseFastItemsStep({
    super.key,
    required this.listScrollController,
    required this.onDraftChanged,
    required this.openAdvancedItemEditor,
    this.lineJustAdded,
    this.onDismissLineJustAdded,
  });

  final ScrollController listScrollController;
  final VoidCallback onDraftChanged;
  final OpenAdvancedItemSheet openAdvancedItemEditor;
  final PurchaseLineDraft? lineJustAdded;
  final VoidCallback? onDismissLineJustAdded;

  @override
  ConsumerState<PurchaseFastItemsStep> createState() =>
      _PurchaseFastItemsStepState();
}

class _PurchaseFastItemsStepState extends ConsumerState<PurchaseFastItemsStep> {
  void _removeAt(int i) {
    ref.read(purchaseDraftProvider.notifier).removeLineAt(i);
    widget.onDraftChanged();
    setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final ok = await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Clear all items?'),
            content: const Text(
              'This removes every line from this purchase.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => ctx.pop(false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => ctx.pop(true),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    ref.read(purchaseDraftProvider.notifier).setLinesFromMaps([]);
    widget.onDraftChanged();
    setState(() {});
  }

  double _approxLinePurchase(PurchaseLineDraft l) {
    final kpu = l.kgPerUnit;
    final pk = l.landingCostPerKg;
    if (kpu != null && pk != null && kpu > 0 && pk > 0) {
      return l.qty * kpu * pk;
    }
    return l.qty * l.landingCost;
  }

  String _qtyHuman(PurchaseLineDraft l) {
    final u = l.unit.trim();
    final q = StrictDecimal.fromObject(l.qty).format(3, trim: true);
    final ul = u.toLowerCase();
    if (l.kgPerUnit != null &&
        l.kgPerUnit! > 0 &&
        (ul == 'bag' || ul == 'sack')) {
      final kg = l.qty * l.kgPerUnit!;
      return '$q $u • ${StrictDecimal.fromObject(kg).format(3, trim: true)} kg';
    }
    return '$q $u';
  }

  String _pRateQuick(PurchaseLineDraft l, Map<String, dynamic>? rateContext) {
    final tl = tradeLineForDisplay(l, rateContext: rateContext);
    final r = tradePurchaseLineDisplayPurchaseRate(tl);
    final d = unit_lbl.purchaseRateSuffix(tl);
    return 'P ₹${r.toStringAsFixed(1)}/$d';
  }

  String _sRateQuick(PurchaseLineDraft l, Map<String, dynamic>? rateContext) {
    final tl = tradeLineForDisplay(l, rateContext: rateContext);
    final r = tradePurchaseLineDisplaySellingRate(tl);
    if (r == null || r <= 0) return 'S —';
    final d = unit_lbl.sellingRateSuffix(tl);
    return 'S ₹${r.toStringAsFixed(1)}/$d';
  }

  Future<void> _editAdvanced(int i) async {
    await widget.openAdvancedItemEditor(editIndex: i);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines =
        ref.watch(purchaseDraftProvider.select((d) => d.lines));
    final supplierId =
        ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final blocked = supplierId == null || supplierId.isEmpty;
    final preview = ref.watch(tradePurchasePreviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pick a supplier on the Party step to add catalog lines.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
                fontSize: 13,
              ),
            ),
          ),
        if (widget.lineJustAdded != null) ...[
          _PurchaseLineAddedPreviewCard(
            line: widget.lineJustAdded!,
            qtyLabel: _qtyHuman(widget.lineJustAdded!),
            amountLabel: _inr0(_approxLinePurchase(widget.lineJustAdded!)),
            onDismiss: widget.onDismissLineJustAdded,
          ),
          const SizedBox(height: 10),
        ],
        Consumer(
          builder: (cx, rf, _) {
            final bd = rf.watch(purchaseStrictBreakdownProvider);
            final qt = rf.watch(purchaseQuantityTotalsProvider);
            final unitBits = <String>[];
            if (qt.totalKg > 1e-6) {
              unitBits.add('${qt.totalKg.toStringAsFixed(0)} KG');
            }
            qt.qtyByUnit.forEach((k, v) {
              if (v > 1e-9) {
                final lk = k.trim().toLowerCase();
                if (lk == 'kg' || lk == 'kgs' || lk == 'kilogram') {
                  return;
                }
                unitBits.add(
                  '${StrictDecimal.fromObject(v).format(3, trim: true)} ${k.toUpperCase()}',
                );
              }
            });
            final qtyLine = unitBits.isEmpty ? '—' : unitBits.join(' • ');
            return Material(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: HexaColors.brandBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TOTAL',
                      style: Theme.of(cx).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.black54,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _inr0(bd.grand),
                      style: Theme.of(cx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      qtyLine,
                      style: Theme.of(cx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Items (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: blocked || lines.isEmpty ? null : _confirmClearAll,
              child: const Text('Clear all'),
            ),
          ],
        ),
        const Divider(height: 16),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      blocked
                          ? 'Supplier required for catalog links.'
                          : 'No items yet. Tap + Add Item below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                  ),
                )
              : ListView.separated(
                  controller: widget.listScrollController,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final ln = lines[i];
                    final rc = tradePreviewLineRateContext(preview, i);
                    final buy = _approxLinePurchase(ln);
                    return Material(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _editAdvanced(i),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ln.itemName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _qtyHuman(ln),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            _pRateQuick(ln, rc),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          backgroundColor:
                                              const Color(0xFFF1F5F9),
                                          side: BorderSide.none,
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            _sRateQuick(ln, rc),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          backgroundColor:
                                              const Color(0xFFECFDF5),
                                          side: BorderSide.none,
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _inr0(buy),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: Color(0xFF0D9488),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _removeAt(i),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: blocked
                ? null
                : () => widget.openAdvancedItemEditor(),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            label: const Text(
              '+ Add Item',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: HexaColors.brandPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseLineAddedPreviewCard extends StatelessWidget {
  const _PurchaseLineAddedPreviewCard({
    required this.line,
    required this.qtyLabel,
    required this.amountLabel,
    this.onDismiss,
  });

  final PurchaseLineDraft line;
  final String qtyLabel;
  final String amountLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFFECFDF5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Added · ${line.itemName}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$qtyLabel · $amountLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0D9488),
                        ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
