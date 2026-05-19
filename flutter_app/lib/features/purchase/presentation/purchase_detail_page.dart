import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/catalog/item_trade_history.dart' show tradeLineToCalc;
import '../../../core/calc_engine.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace;
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/purchase_invoice_pdf_layout.dart'
    show tradeCalcRequestFromTradePurchase;
import '../../../core/services/purchase_pdf.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/utils/snack.dart';
import '../../../core/utils/trade_purchase_commission.dart';
import '../../../core/utils/trade_purchase_rate_display.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../core/utils/unit_classifier.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../providers/trade_purchase_detail_provider.dart';

String _inr(num n, {int fractionDigits = 2}) =>
    NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: fractionDigits,
    ).format(n);

String _qtyFmt(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

double _lineInclusive(TradePurchaseLine l) {
  return l.lineTotal ?? lineMoney(tradeLineToCalc(l));
}

double _lineKg(TradePurchaseLine l) {
  return ledgerTradeLineWeightKg(
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
}

String _unitClassificationHint(TradePurchaseLine l) {
  final clf = UnitClassifier.classify(
    itemName: l.itemName,
    lineUnit: l.unit,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
  );
  return switch (clf.type) {
    UnitType.weightBag => 'Class: weight bag',
    UnitType.singlePack => clf.kgFromName != null && clf.kgFromName! > 0
        ? 'Class: single pack (${clf.kgFromName} kg)'
        : 'Class: single pack',
    UnitType.multiPackBox => 'Class: multi-pack box',
  };
}

double? _effectiveLineProfit(TradePurchaseLine l) {
  if (l.lineProfit != null) return l.lineProfit;
  final hasSell = (l.sellingRate ?? l.sellingCost) != null;
  if (!hasSell) return null;
  return l.sellingGross - l.landingGross;
}

class _Agg {
  const _Agg({
    required this.linesInclusive,
    required this.afterHeaderDiscount,
    required this.discountRupeeEffect,
    required this.headerDiscountPct,
    required this.freight,
    required this.freightIncluded,
    required this.commission,
    required this.billty,
    required this.delivered,
    required this.finalComputed,
    required this.totalKg,
    required this.totalBags,
    required this.totalBox,
    required this.totalTin,
    required this.sumLandingGross,
    required this.sumSellingGross,
    required this.sumProfit,
  });

  final double linesInclusive;
  final double afterHeaderDiscount;
  final double discountRupeeEffect;
  final double headerDiscountPct;
  final double freight;
  final bool freightIncluded;
  final double commission;
  final double billty;
  final double delivered;
  final double finalComputed;
  final double totalKg;
  final double totalBags;
  final double totalBox;
  final double totalTin;
  final double sumLandingGross;
  final double sumSellingGross;
  final double sumProfit;
}

_Agg _buildAgg(TradePurchase p) {
  var linesInclusive = 0.0;
  var sumLandingGross = 0.0;
  var sumSellingGross = 0.0;
  var profitSum = 0.0;
  var kg = 0.0;
  var bags = 0.0;
  var boxes = 0.0;
  var tins = 0.0;

  for (final l in p.lines) {
    linesInclusive += _lineInclusive(l);
    sumLandingGross += l.landingGross;
    sumSellingGross += l.sellingGross;
    final pr = _effectiveLineProfit(l);
    if (pr != null) profitSum += pr;
    kg += _lineKg(l);
    final rawU = l.unit.trim().toLowerCase();
    final u = rawU == 'sack' ? 'bag' : rawU;
    if (u == 'bag') {
      bags += l.qty;
    } else if (u == 'box') {
      boxes += l.qty;
    } else if (u == 'tin') {
      tins += l.qty;
    }
  }

  if (p.totalLineProfit != null) {
    profitSum = p.totalLineProfit!;
  }

  final req = tradeCalcRequestFromTradePurchase(p);
  final totals = computeTradeTotals(req);
  final hdr = p.discount ?? 0.0;
  final clippedHdr = hdr > 100 ? 100.0 : (hdr < 0 ? 0.0 : hdr);
  final afterHd = clippedHdr <= 0
      ? linesInclusive
      : linesInclusive - linesInclusive * (clippedHdr / 100);

  final included = req.freightType == 'included';
  final fr = req.freightAmount != null && req.freightAmount! > 0 && !included
      ? req.freightAmount!
      : 0.0;

  return _Agg(
    linesInclusive: linesInclusive,
    afterHeaderDiscount: afterHd,
    discountRupeeEffect: linesInclusive - afterHd,
    headerDiscountPct: clippedHdr,
    freight: fr,
    freightIncluded: included,
    commission: tradePurchaseCommissionInr(p),
    billty: req.billtyRate ?? 0.0,
    delivered: req.deliveredRate ?? 0.0,
    finalComputed: totals.amountSum,
    totalKg: kg,
    totalBags: bags,
    totalBox: boxes,
    totalTin: tins,
    sumLandingGross: sumLandingGross,
    sumSellingGross: sumSellingGross,
    sumProfit: profitSum,
  );
}

class PurchaseDetailPage extends ConsumerStatefulWidget {
  const PurchaseDetailPage({
    super.key,
    required this.purchaseId,
    this.seedPurchase,
  });

  final String purchaseId;
  /// Optional row from list/ledger while GET detail runs (same [id] as [purchaseId]).
  final TradePurchase? seedPurchase;

  @override
  ConsumerState<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends ConsumerState<PurchaseDetailPage> {
  Timer? _slowLoadTimer;
  bool _slowLoadPastSkeleton = false;
  bool _slowLoadTimerArmed = false;

  @override
  void dispose() {
    _slowLoadTimer?.cancel();
    super.dispose();
  }

  void _syncDetailLoadUi(AsyncValue<TradePurchase> async, bool seedOk) {
    final loadingNoSeed = async.isLoading && !seedOk;
    if (!loadingNoSeed) {
      _slowLoadTimer?.cancel();
      _slowLoadTimer = null;
      _slowLoadTimerArmed = false;
      if (_slowLoadPastSkeleton) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _slowLoadPastSkeleton = false);
        });
      }
      return;
    }
    if (_slowLoadTimerArmed) return;
    _slowLoadTimerArmed = true;
    _slowLoadTimer?.cancel();
    _slowLoadTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _slowLoadTimer = null;
      _slowLoadTimerArmed = false;
      setState(() => _slowLoadPastSkeleton = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tradePurchaseDetailProvider(widget.purchaseId));
    final seed = widget.seedPurchase;
    final seedOk = seed != null && seed.id == widget.purchaseId;
    _syncDetailLoadUi(async, seedOk);

    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () {
        if (seedOk) {
          return _LoadedPurchaseScaffold(
            p: seed,
            showRefreshBanner: true,
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.popOrGo('/purchase'),
            ),
            title: const Text('Purchase'),
            backgroundColor: Colors.transparent,
            foregroundColor: HexaColors.brandPrimary,
          ),
          body: _slowLoadPastSkeleton
              ? _DetailSlowLoadBody(
                  onRetry: () {
                    setState(() {
                      _slowLoadPastSkeleton = false;
                      _slowLoadTimerArmed = false;
                    });
                    ref.invalidate(tradePurchaseDetailProvider(widget.purchaseId));
                  },
                )
              : const DetailSkeleton(),
        );
      },
      error: (e, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.popOrGo('/purchase'),
            ),
            title: const Text('Purchase'),
            backgroundColor: Colors.transparent,
            foregroundColor: HexaColors.brandPrimary,
          ),
          body: HexaErrorCard.fromError(
            error: e,
            title: 'Could not load purchase',
            onRetry: () =>
                ref.invalidate(tradePurchaseDetailProvider(widget.purchaseId)),
          ),
        );
      },
      data: (p) => _LoadedPurchaseScaffold(p: p),
    );
  }
}

/// After [DetailSkeleton] window (~1.5s), show a lighter wait state + inline retry.
class _DetailSlowLoadBody extends StatelessWidget {
  const _DetailSlowLoadBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFFFF7ED),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Still loading this purchase — weak signal or large bill. '
                    'You can wait or tap Retry.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1C1917),
                          height: 1.3,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'Fetching latest lines…',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadedPurchaseScaffold extends ConsumerWidget {
  const _LoadedPurchaseScaffold({
    required this.p,
    this.showRefreshBanner = false,
  });

  final TradePurchase p;
  final bool showRefreshBanner;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      if (!context.mounted) return;
      showTopSnack(context, 'Deleted');
      context.popOrGo('/purchase');
    } catch (e) {
      if (!context.mounted) return;
      showTopSnack(
        context,
        e is DioException ? friendlyApiError(e) : 'Could not delete',
        isError: true,
      );
    }
  }

  Future<void> _runPrintPdf(BuildContext context, WidgetRef ref) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    final ok = await printPurchasePdf(p, biz);
    if (!context.mounted) return;
    if (!ok) {
      showTopSnack(
        context,
        'Could not print PDF. Try again.',
        isError: true,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => _runPrintPdf(context, ref),
        ),
      );
      return;
    }
  }

  Future<void> _runSharePdf(BuildContext context, WidgetRef ref) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    try {
      final ok = await sharePurchasePdf(p, biz);
      if (!context.mounted) return;
      if (ok) {
        if (!context.mounted) return;
        showTopSnack(context, 'PDF ready to share');
      } else {
        showTopSnack(
          context,
          'Could not export PDF. Check connection and retry.',
          isError: true,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _runSharePdf(context, ref),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showTopSnack(context, 'Export error: $e', isError: true);
    }
  }


  Future<void> _runDownloadPdf(BuildContext context, WidgetRef ref) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    final ok = await downloadPurchasePdf(p, biz);
    if (!context.mounted) return;
    if (!ok) {
      showTopSnack(
        context,
        'Could not open PDF. Try again.',
        isError: true,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _runDownloadPdf(context, ref),
        ),
      );
      return;
    }
    if (kIsWeb) {
      showTopSnack(
        context,
        'Use the browser print/save dialog to download PDF',
      );
    } else {
      showTopSnack(
        context,
        'Use Save as PDF or share from the dialog to save the file',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optim = ref.watch(tradePurchaseDeliveryOptimisticProvider(p.id));
    final displayP = optim == null ? p : p.withDelivered(optim);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/purchase'),
        ),
        title: Text(p.humanId),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: p.statusEnum == PurchaseStatus.cancelled
                ? null
                : () => context.push('/purchase/edit/${p.id}'),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _runSharePdf(context, ref),
          ),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _runPrintPdf(context, ref),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _runDownloadPdf(context, ref),
          ),
          if (p.statusEnum != PurchaseStatus.cancelled)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context, ref);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          color: Theme.of(ctx).colorScheme.error, size: 22),
                      const SizedBox(width: 12),
                      Text('Delete purchase',
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showRefreshBanner) ...[
            const LinearProgressIndicator(minHeight: 2),
            Material(
              color: const Color(0xFFE8F4F2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Refreshing latest totals…',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F766E),
                      ),
                ),
              ),
            ),
          ],
          Expanded(child: _PurchaseDetailBody(p: displayP)),
        ],
      ),
    );
  }
}

class _PurchaseDetailBody extends ConsumerStatefulWidget {
  const _PurchaseDetailBody({required this.p});

  final TradePurchase p;

  @override
  ConsumerState<_PurchaseDetailBody> createState() => _PurchaseDetailBodyState();
}

class _PurchaseDetailBodyState extends ConsumerState<_PurchaseDetailBody> {
  Future<void> _toggleDelivery(
    BuildContext context,
    WidgetRef ref,
    TradePurchase p,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final newDelivered = !p.isDelivered;
    ref.read(tradePurchaseDeliveryOptimisticProvider(p.id).notifier).state =
        newDelivered;
    showTopSnack(
      context,
      newDelivered ? '✅ Marked as delivered' : 'Marked as pending delivery',
    );
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: newDelivered,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      ref.read(tradePurchaseDeliveryOptimisticProvider(p.id).notifier).state =
          null;
    } catch (e) {
      ref.read(tradePurchaseDeliveryOptimisticProvider(p.id).notifier).state =
          null;
      if (context.mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not update delivery status. Try again.',
          isError: true,
        );
      }
    }
  }

  Widget _buildSummaryStrip(BuildContext context, _Agg agg, ColorScheme cs) {
    final profit = agg.sumProfit;
    final profitColor =
        profit >= 0 ? const Color(0xFF1B6B5A) : Colors.red.shade700;

    String buildWeightText() {
      final kg = formatLineQtyWeight(qty: agg.totalKg, unit: 'kg');
      final parts = <String>[];
      if (agg.totalBags > 1e-6) parts.add('${_qtyFmt(agg.totalBags)} bags');
      if (agg.totalBox > 1e-6) parts.add('${_qtyFmt(agg.totalBox)} boxes');
      if (agg.totalTin > 1e-6) parts.add('${_qtyFmt(agg.totalTin)} tins');
      if (parts.isEmpty) return kg;
      return '$kg\n${parts.join(' · ')}';
    }

    Widget summaryCol(String label, String value, Color valueColor) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            summaryCol(
              'AMOUNT',
              _inr(agg.finalComputed, fractionDigits: 0),
              cs.onSurface,
            ),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            summaryCol('WEIGHT', buildWeightText(), cs.onSurface),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            summaryCol(
              'PROFIT',
              _inr(profit, fractionDigits: 0),
              profitColor,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final agg = _buildAgg(p);
    final cs = Theme.of(context).colorScheme;
    final st = p.statusEnum;
    final paidPending = st == PurchaseStatus.paid ||
        (p.remaining <= 0.009 && st != PurchaseStatus.cancelled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(tradePurchaseDetailProvider(p.id));
                await ref.read(tradePurchaseDetailProvider(p.id).future);
              },
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.hasMissingDetails) _pendingDetailsChip(context, p, cs),
                    _compactMeta(context, p, st, paidPending, cs),
                    const SizedBox(height: 18),
                    _buildSummaryStrip(context, agg, cs),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        'Qty · ${purchaseHistoryPackSummary(p)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface.withValues(alpha: 0.82),
                              height: 1.25,
                            ),
                      ),
                    ),
                    Material(
                      color: p.isDelivered
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: p.isDelivered
                                ? Colors.green.shade300
                                : Colors.orange.shade400,
                            width: p.isDelivered ? 1 : 2.5,
                          ),
                        ),
                        child: ListTile(
                            leading: Icon(
                              p.isDelivered
                                  ? Icons.check_circle
                                  : Icons.local_shipping,
                              color: p.isDelivered
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                            title: Text(
                              p.isDelivered
                                  ? 'Received at warehouse'
                                  : 'Pending delivery',
                            ),
                            subtitle: p.deliveredAt != null
                                ? Text(
                                    'Received on ${DateFormat('MMM d, y').format(p.deliveredAt!)}',
                                  )
                                : const Text(
                                    'Not yet confirmed as received',
                                  ),
                            trailing: TextButton(
                              onPressed: () =>
                                  _toggleDelivery(context, ref, p),
                              child: Text(
                                p.isDelivered
                                    ? 'Mark Pending'
                                    : 'Mark Received',
                              ),
                            ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Items',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                    ),
                    const SizedBox(height: 10),
                    ..._itemsAsCards(context, p, cs),
                    const SizedBox(height: 18),
                    _chargesAndBalanceCollapsible(context, p, agg, cs),
                  ],
                ),
              ),
            ),
          ),
        ),
        _stickyActionBar(context, ref, p, cs),
      ],
    );
  }

  Widget _pendingDetailsChip(
      BuildContext context, TradePurchase p, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.edit_note_rounded,
              size: 18, color: Colors.amber.shade900),
          label: Text(
            'Details pending — tap to complete',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
          backgroundColor: Colors.amber.shade50,
          side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.35)),
          onPressed: () => context.push('/purchase/edit/${p.id}'),
        ),
      ),
    );
  }

  Widget _compactMeta(
    BuildContext context,
    TradePurchase p,
    PurchaseStatus st,
    bool paidPending,
    ColorScheme cs,
  ) {
    final sup = (p.supplierName ?? '—').trim();
    final bro = (p.brokerName ?? '—').trim();
    final broImg = (p.brokerImageUrl ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                sup.isEmpty ? '—' : sup,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                paidPending ? 'Paid' : st.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: st.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _brokerAvatar(broImg, bro.isEmpty ? '—' : bro),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Broker: ${bro.isEmpty ? '—' : bro}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('d MMM yyyy').format(p.purchaseDate),
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        if (p.paymentDays != null)
          Text(
            'Payment: ${p.paymentDays} days',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        if (p.invoiceNumber != null && p.invoiceNumber!.trim().isNotEmpty)
          Text(
            'Ref: ${p.invoiceNumber!.trim()}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _brokerAvatar(String imageUrl, String name) {
    final initials = name.trim().isEmpty
        ? '—'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
    if (imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: const Color(0xFFE5E7EB),
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFF1B6B5A),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _chargesAndBalanceCollapsible(
    BuildContext context,
    TradePurchase p,
    _Agg agg,
    ColorScheme cs,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: Text(
          'Charges & balance',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        subtitle: Text(
          'Freight, commission, payment',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: [
          _miniCharges(context, agg, cs),
          const SizedBox(height: 8),
          _balanceRows(context, p, cs),
          // Total mismatch warning removed from UI — totals are now kept in parity
          // by computeTradeTotals + stored total updates; showing this confuses users.
        ],
      ),
    );
  }

  Widget _balanceRows(BuildContext context, TradePurchase p, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Balance',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              SelectableText(
                _inr(p.remaining),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          if (p.dueDate != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Due',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                Text(
                  DateFormat.yMMMd().format(p.dueDate!),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  ({String purchase, String selling}) _lineRateLabels(TradePurchaseLine l) {
    final pk = tradePurchaseLineDisplayPurchaseRate(l);
    final sk = tradePurchaseLineDisplaySellingRate(l);
    final pDim = unit_lbl.purchaseRateSuffix(l);
    final purchase = '${_inr(pk)}/$pDim';
    if (sk != null) {
      final sDim = unit_lbl.sellingRateSuffix(l);
      return (purchase: purchase, selling: '${_inr(sk)}/$sDim');
    }
    if (l.kgPerUnit != null &&
        l.landingCostPerKg != null &&
        l.kgPerUnit! > 0 &&
        l.landingCostPerKg! > 0) {
      final kgQty = l.qty * l.kgPerUnit!;
      if (kgQty > 1e-9) {
        final implied = l.sellingGross / kgQty;
        final dim = unit_lbl.sellingRateSuffix(l);
        return (purchase: purchase, selling: '${_inr(implied)}/$dim');
      }
    }
    return (purchase: purchase, selling: '—');
  }

  String _lineQtyHuman(TradePurchaseLine l) =>
      formatLineQtyWeightFromTradeLine(l);

  List<Widget> _itemsAsCards(
      BuildContext context, TradePurchase p, ColorScheme cs) {
    final out = <Widget>[];
    var i = 0;
    for (final l in p.lines) {
      i++;
      final pr = _effectiveLineProfit(l);
      final rates = _lineRateLabels(l);
      final profitColor =
          pr == null ? cs.onSurfaceVariant : (pr >= 0 ? const Color(0xFF0F766E) : HexaColors.loss);
      out.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$i.',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: _unitClassificationHint(l),
                      child: Text(
                        l.itemName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _lineQtyHuman(l),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'P: ${rates.purchase}  ·  S: ${rates.selling}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Line total',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  SelectableText(
                    _inr(_lineInclusive(l)),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ],
              ),
              if (pr != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profit',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    SelectableText(
                      _inr(pr),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: profitColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _miniCharges(BuildContext context, _Agg agg, ColorScheme cs) {
    Widget tiny(String k, String v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              k,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            SelectableText(
              v,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    if (agg.headerDiscountPct > 1e-6) {
      rows.add(tiny(
        'Purchase discount',
        '${agg.headerDiscountPct.toStringAsFixed(1)}% (−${_inr(agg.discountRupeeEffect)})',
      ));
    }
    rows.add(tiny(
      'Freight',
      agg.freightIncluded ? 'Included' : (agg.freight > 1e-6 ? _inr(agg.freight) : '—'),
    ));
    rows.add(tiny('Commission', agg.commission > 1e-6 ? _inr(agg.commission) : '—'));
    rows.add(tiny('Billty', agg.billty > 1e-6 ? _inr(agg.billty) : '—'));
    rows.add(tiny('Delivered', agg.delivered > 1e-6 ? _inr(agg.delivered) : '—'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _stickyActionBar(
    BuildContext context,
    WidgetRef ref,
    TradePurchase p,
    ColorScheme cs,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    Widget cell(Widget child) => Expanded(child: child);

    Future<void> share() async {
      final biz = ref.read(invoiceBusinessProfileProvider);
      try {
        final ok = await sharePurchasePdf(p, biz);
        if (!context.mounted) return;
        if (!ok) {
          showTopSnack(
            context,
            'Could not export PDF. Check connection and retry.',
            isError: true,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => share(),
            ),
          );
          return;
        }
      } catch (e) {
        if (!context.mounted) return;
        showTopSnack(context, 'Failed to export PDF.', isError: true);
      }
      if (!context.mounted) return;
      showTopSnack(context, 'PDF ready to share');
    }

    Future<void> printPdf() async {
      final biz = ref.read(invoiceBusinessProfileProvider);
      final ok = await printPurchasePdf(p, biz);
      if (!context.mounted) return;
      if (!ok) {
        showTopSnack(
          context,
          'Could not print PDF. Try again.',
          isError: true,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => printPdf(),
          ),
        );
      }
    }

    Future<void> downloadPdf() async {
      final biz = ref.read(invoiceBusinessProfileProvider);
      final ok = await downloadPurchasePdf(p, biz);
      if (!context.mounted) return;
      if (!ok) {
        showTopSnack(
          context,
          'Could not open PDF. Try again.',
          isError: true,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => downloadPdf(),
          ),
        );
        return;
      }
      if (kIsWeb) {
        showTopSnack(
          context,
          'Use the browser print/save dialog to download PDF',
        );
      } else {
        showTopSnack(
          context,
          'Use Save as PDF or share from the dialog to save the file',
        );
      }
    }

    return Material(
      elevation: 10,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.statusEnum != PurchaseStatus.paid &&
                p.statusEnum != PurchaseStatus.cancelled)
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _markPaidSheet(context, ref, p),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Mark as Paid'),
                ),
              ),
            if (p.statusEnum != PurchaseStatus.paid &&
                p.statusEnum != PurchaseStatus.cancelled)
              const SizedBox(height: 10),
            Row(
              children: [
                cell(
                  OutlinedButton.icon(
                    onPressed: p.statusEnum == PurchaseStatus.cancelled
                        ? null
                        : () => context.push('/purchase/edit/${p.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                cell(
                  OutlinedButton.icon(
                    onPressed: share,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 8),
                cell(
                  OutlinedButton.icon(
                    onPressed: printPdf,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 8),
                cell(
                  OutlinedButton.icon(
                    onPressed: downloadPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markPaidSheet(BuildContext context, WidgetRef ref, TradePurchase p) async {
    final ctrl = TextEditingController(text: p.remaining.toStringAsFixed(2));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Record payment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount paid (total on purchase)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ctx.pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(ctrl.text.trim());
    if (v == null || v < 0) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).patchPurchasePayment(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            paidAmount: v,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DioException
                  ? friendlyApiError(e)
                  : 'Something went wrong. Please try again.',
            ),
          ),
        );
      }
    }
  }
}
