import 'dart:async';

import 'package:dio/dio.dart';
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
    show
        invalidateAfterDeliveryCommit,
        invalidateAfterDeliveryVerify,
        invalidateAfterPurchaseDelete,
        invalidatePurchaseWorkspace;
import '../../../core/providers/delivery_pipeline_provider.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/stock_offline_queue_provider.dart';
import '../../../core/utils/delivery_offline_actions.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/services/pdf_actions.dart';
import '../../../core/services/purchase_export_service.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/services/purchase_invoice_pdf_layout.dart'
    show tradeCalcRequestFromTradePurchase;
import '../../../core/utils/line_display.dart';
import 'widgets/purchase_detail_action_bar.dart';
import 'widgets/purchase_detail_delivery_banner.dart';
import 'widgets/purchase_delivery_timeline.dart';
import 'widgets/purchase_detail_header.dart';
import 'widgets/purchase_detail_line_row.dart';
import 'widgets/purchase_detail_summary_strip.dart';
import 'widgets/staff_verification_sheet.dart';
import '../../../core/utils/snack.dart';
import '../../../core/utils/trade_purchase_commission.dart';
import '../../../core/utils/trade_purchase_rate_display.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/units/dynamic_unit_label_engine.dart' as unit_lbl;
import '../../../core/utils/unit_classifier.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../providers/trade_purchase_detail_provider.dart';

String _inr(num n, {int fractionDigits = 2}) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: fractionDigits,
    ).format(n);

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

String _purchaseHistoryBackRoute(WidgetRef ref) {
  final session = ref.read(sessionProvider);
  if (session != null && sessionIsStaff(session)) {
    return '/staff/purchase-history';
  }
  return '/purchase';
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
              onPressed: () => context.popOrGo(_purchaseHistoryBackRoute(ref)),
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
                    ref.invalidate(
                        tradePurchaseDetailProvider(widget.purchaseId));
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
              onPressed: () => context.popOrGo(_purchaseHistoryBackRoute(ref)),
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
                Icon(Icons.hourglass_top_rounded,
                    color: Colors.orange.shade800),
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
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Delete')),
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
      invalidateAfterPurchaseDelete(ref, purchase: p);
      if (!context.mounted) return;
      showTopSnack(context, 'Deleted');
      context.popOrGo(_purchaseHistoryBackRoute(ref));
    } catch (e) {
      if (!context.mounted) return;
      showTopSnack(
        context,
        e is DioException ? friendlyApiError(e) : 'Could not delete',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hideFinancials = session != null && !sessionCanSeeFinancials(session);
    final optim = ref.watch(tradePurchaseDeliveryOptimisticProvider(p.id));
    final displayP = optim == null ? p : p.withDelivered(optim);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo(_purchaseHistoryBackRoute(ref)),
        ),
        title: Text(p.humanId),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          if (p.statusEnum != PurchaseStatus.cancelled && !hideFinancials)
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Expanded(
            child: PurchaseDetailBody(
              p: displayP,
              hideFinancials: hideFinancials,
            ),
          ),
        ],
      ),
    );
  }
}

class PurchaseDetailBody extends ConsumerStatefulWidget {
  const PurchaseDetailBody({
    super.key,
    required this.p,
    this.hideFinancials = false,
    this.embedded = false,
  });

  final TradePurchase p;
  final bool hideFinancials;

  /// True when shown in desktop master-detail pane (no outer scaffold).
  final bool embedded;

  @override
  ConsumerState<PurchaseDetailBody> createState() => PurchaseDetailBodyState();
}

class PurchaseDetailBodyState extends ConsumerState<PurchaseDetailBody> {
  bool _isOwnerOrManager() {
    final session = ref.read(sessionProvider);
    if (session == null) return false;
    final role = session.primaryBusiness.role;
    return session.isSuperAdmin ||
        role == 'owner' ||
        role == 'manager' ||
        role == 'admin';
  }

  bool _isStaff() {
    final session = ref.read(sessionProvider);
    if (session == null) return false;
    return session.primaryBusiness.role == 'staff';
  }

  Set<String> _purchaseItemIds(TradePurchase purchase) {
    return purchase.lines
        .map((l) => l.catalogItemId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> _afterDeliveryMutation(
    BuildContext context,
    TradePurchase purchase,
    String message,
  ) async {
    invalidateAfterDeliveryCommit(
      ref,
      purchaseId: purchase.id,
      affectedItemIds: _purchaseItemIds(purchase),
    );
    if (context.mounted) showTopSnack(context, message);
  }

  Future<void> _dispatch(BuildContext context, TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final truckCtrl = TextEditingController();
    final driverCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var markInTransit = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mark dispatched'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: truckCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Truck number (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: driverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Driver contact (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dispatch note (optional)',
                  ),
                  maxLines: 2,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Already in transit'),
                  value: markInTransit,
                  onChanged: (v) => setLocal(() => markInTransit = v == true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) {
      truckCtrl.dispose();
      driverCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    try {
      final updated = await ref.read(hexaApiProvider).dispatchPurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            truckNumber: truckCtrl.text,
            driverContact: driverCtrl.text,
            dispatchNote: noteCtrl.text,
            markInTransit: markInTransit,
          );
      await _afterDeliveryMutation(
        context,
        TradePurchase.fromJson(updated),
        'Marked as dispatched',
      );
    } catch (e) {
      if (context.mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not update dispatch. Try again.',
          isError: true,
        );
      }
    } finally {
      truckCtrl.dispose();
      driverCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _arrive(BuildContext context, TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final result = await markPurchaseArrivedResilient(
        ref: ref,
        businessId: session.primaryBusiness.id,
        purchaseId: p.id,
      );
      if (result.queued) {
        invalidatePurchaseWorkspace(
          ref,
          affectedItemIds: _purchaseItemIds(p),
        );
        ref.invalidate(deliveryPipelineProvider);
        ref.invalidate(tradePurchaseDetailProvider(p.id));
        ref.invalidate(stockOfflinePendingCountProvider);
        if (context.mounted) {
          showTopSnack(
            context,
            'Saved offline — will sync when online',
          );
        }
        return;
      }
      await _afterDeliveryMutation(
        context,
        TradePurchase.fromJson(result.body!),
        'Marked arrived at warehouse',
      );
    } catch (e) {
      if (context.mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not mark arrival. Try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _verify(BuildContext context, TradePurchase p) async {
    final lineMaps = [
      for (final l in p.lines)
        {
          'id': l.id,
          'item_name': l.itemName,
          'qty': l.qty,
          'unit': l.unit,
        }
    ];
    final changed = await showStaffVerificationSheet(
      context: context,
      ref: ref,
      purchaseId: p.id,
      lines: lineMaps,
    );
    invalidateAfterDeliveryVerify(ref, purchaseId: p.id);
    if (changed && context.mounted) {
      showTopSnack(context, 'Counts submitted — owner can commit to stock');
    }
  }

  Future<void> _commitStock(BuildContext context, TradePurchase p) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Commit stock to warehouse?'),
            content: Text(
              'This will add stock for ${p.lines.length} line(s) from ${p.humanId}. '
              'This cannot be undone without reverting delivery.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Commit stock'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final updated = await ref.read(hexaApiProvider).commitPurchaseDelivery(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      final purchase = TradePurchase.fromJson(updated);
      final applied = (updated['stock_updates'] is List)
          ? (updated['stock_updates'] as List).where((row) {
              if (row is! Map) return false;
              if (row['needs_unit_setup'] == true) return false;
              return true;
            }).length
          : purchase.stockUpdatesCount;
      final needsSetup = (updated['stock_updates'] is List)
          ? (updated['stock_updates'] as List)
              .where((row) => row is Map && row['needs_unit_setup'] == true)
              .length
          : 0;
      final n = applied > 0 ? applied : p.lines.length;
      var message = n == 1
          ? 'Stock added to warehouse · 1 item'
          : 'Stock added to warehouse · $n items';
      if (needsSetup > 0) {
        message =
            '$message · $needsSetup item${needsSetup == 1 ? '' : 's'} need unit setup in catalog';
      }
      await _afterDeliveryMutation(context, purchase, message);
    } catch (e) {
      if (context.mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not commit to stock. Try again.',
          isError: true,
        );
      }
    }
  }

  Future<void> _revertDelivery(BuildContext context, TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Revert delivery?'),
            content: const Text(
              'This will reverse stock added for this purchase and reset delivery to pending.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Revert stock'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      final updated = await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: false,
          );
      final purchase = TradePurchase.fromJson(updated);
      await _afterDeliveryMutation(
        context,
        purchase,
        'Delivery reverted · stock reversed',
      );
    } catch (e) {
      if (context.mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not revert delivery. Try again.',
          isError: true,
        );
      }
    }
  }

  List<Widget> _lineRows(
    BuildContext context,
    TradePurchase p,
    ColorScheme cs,
    bool hideFinancials,
  ) {
    final out = <Widget>[];
    var i = 0;
    for (final l in p.lines) {
      i++;
      final pr = hideFinancials ? null : _effectiveLineProfit(l);
      final rates = hideFinancials ? null : _lineRateLabels(l);
      final profitColor = pr == null
          ? cs.onSurfaceVariant
          : (pr >= 0 ? const Color(0xFF0F766E) : HexaColors.loss);
      out.add(
        PurchaseDetailLineRow(
          index: i,
          line: l,
          qtyLabel: _lineQtyHuman(l),
          purchaseRateLabel: rates?.purchase ?? '—',
          sellingRateLabel: rates?.selling ?? '—',
          lineTotalLabel: _inr(_lineInclusive(l)),
          profitLabel: pr != null ? _inr(pr) : null,
          profitColor: profitColor,
          unitHint: _unitClassificationHint(l),
          hideFinancials: hideFinancials,
        ),
      );
    }
    return out;
  }

  Widget _mainColumn(
    BuildContext context,
    TradePurchase p,
    _Agg agg,
    ColorScheme cs,
    bool hideFinancials,
    bool paidPending,
    PurchaseStatus st,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.hasMissingDetails) _pendingDetailsChip(context, p, cs),
        PurchaseDetailHeader(
          purchase: p,
          status: st,
          paidPending: paidPending,
        ),
        if (!hideFinancials) ...[
          const SizedBox(height: 14),
          PurchaseDetailSummaryStrip(
            amountLabel: _inr(agg.finalComputed, fractionDigits: 0),
            weightPrimary: formatPurchaseSummaryWeight(
              totalKg: agg.totalKg,
              totalBags: agg.totalBags,
              totalBox: agg.totalBox,
              totalTin: agg.totalTin,
            ),
            weightSecondary: formatPurchaseSummaryWeightSecondary(
              totalKg: agg.totalKg,
              totalBags: agg.totalBags,
              totalBox: agg.totalBox,
              totalTin: agg.totalTin,
            ),
            profitLabel: _inr(agg.sumProfit, fractionDigits: 0),
            profitColor: agg.sumProfit >= 0
                ? const Color(0xFF1B6B5A)
                : Colors.red.shade700,
          ),
        ] else
          const SizedBox(height: 12),
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
        const SizedBox(height: 8),
        PurchaseDetailDeliveryBanner(
          purchase: p,
          isOwnerOrManager: _isOwnerOrManager(),
          isStaff: _isStaff(),
          onDispatch: _isOwnerOrManager()
              ? () => _dispatch(context, p)
              : null,
          onArrive: _isStaff() ? () => _arrive(context, p) : null,
          onVerify: (_isStaff() || _isOwnerOrManager())
              ? () => _verify(context, p)
              : null,
          onCommit: _isOwnerOrManager()
              ? () => _commitStock(context, p)
              : null,
          onRevert: _isOwnerOrManager()
              ? () => _revertDelivery(context, p)
              : null,
        ),
        const SizedBox(height: 12),
        PurchaseDeliveryTimeline(purchase: p),
        const SizedBox(height: 14),
        Text(
          'Items',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(height: 8),
        ..._lineRows(context, p, cs, hideFinancials),
      ],
    );
  }

  Future<void> _runExport(
    BuildContext context, {
    required Future<PdfActionResult> Function() action,
    required VoidCallback onRetry,
  }) async {
    showTopSnack(context, 'Preparing PDF…');
    final result = await action();
    if (!context.mounted) return;
    if (!result.ok) {
      showTopSnack(
        context,
        result.message,
        isError: true,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: onRetry,
        ),
      );
      return;
    }
    showTopSnack(context, result.message);
  }

  Widget _sidePanel(
    BuildContext context,
    TradePurchase p,
    _Agg agg,
    ColorScheme cs,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: _chargesAndBalanceCollapsible(context, p, agg, cs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final hideFinancials = widget.hideFinancials;
    final agg = _buildAgg(p);
    final cs = Theme.of(context).colorScheme;
    final st = p.statusEnum;
    final paidPending = st == PurchaseStatus.paid ||
        (p.remaining <= 0.009 && st != PurchaseStatus.cancelled);
    final desktop =
        MediaQuery.sizeOf(context).width >= kDesktopMin;
    final biz = ref.read(invoiceBusinessProfileProvider);

    final api = ref.read(hexaApiProvider);
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    Future<void> sharePdf() => _runExport(
          context,
          action: () => exportSharePurchase(
            p,
            biz,
            api: api,
            businessId: bid,
          ),
          onRetry: sharePdf,
        );
    Future<void> printPdf() => _runExport(
          context,
          action: () => exportPrintPurchase(
            p,
            biz,
            api: api,
            businessId: bid,
          ),
          onRetry: printPdf,
        );
    Future<void> downloadPdf() => _runExport(
          context,
          action: () => exportDownloadPurchase(
            p,
            biz,
            api: api,
            businessId: bid,
          ),
          onRetry: downloadPdf,
        );

    Widget wrapRefresh(Widget child) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tradePurchaseDetailProvider(p.id));
            await ref.read(tradePurchaseDetailProvider(p.id).future);
          },
          child: child,
        );

    final mainColumn = _mainColumn(
      context,
      p,
      agg,
      cs,
      hideFinancials,
      paidPending,
      st,
    );

    final Widget body;
    if (desktop && !hideFinancials) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 58,
            child: wrapRefresh(
              SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: mainColumn,
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(flex: 42, child: _sidePanel(context, p, agg, cs)),
        ],
      );
    } else {
      final slivers = <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(child: mainColumn),
        ),
        if (!hideFinancials)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _chargesAndBalanceCollapsible(context, p, agg, cs),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ];
      body = wrapRefresh(
        CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: slivers,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SafeArea(bottom: false, child: body),
        ),
        PurchaseDetailActionBar(
          purchase: p,
          hideFinancials: hideFinancials,
          onMarkPaid: p.statusEnum != PurchaseStatus.paid &&
                  p.statusEnum != PurchaseStatus.cancelled
              ? () => _markPaidSheet(context, ref, p)
              : null,
          onEdit: p.statusEnum == PurchaseStatus.cancelled
              ? null
              : () => context.push('/purchase/edit/${p.id}'),
          onExportPdf: downloadPdf,
          onShare: sharePdf,
          onPrint: printPdf,
        ),
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
          side:
              BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.35)),
          onPressed: () => context.push('/purchase/edit/${p.id}'),
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
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
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
      agg.freightIncluded
          ? 'Included'
          : (agg.freight > 1e-6 ? _inr(agg.freight) : '—'),
    ));
    rows.add(
        tiny('Commission', agg.commission > 1e-6 ? _inr(agg.commission) : '—'));
    rows.add(tiny('Billty', agg.billty > 1e-6 ? _inr(agg.billty) : '—'));
    rows.add(
        tiny('Delivered', agg.delivered > 1e-6 ? _inr(agg.delivered) : '—'));
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Future<void> _markPaidSheet(
      BuildContext context, WidgetRef ref, TradePurchase p) async {
    final ctrl = TextEditingController(text: p.remaining.toStringAsFixed(2));
    final ok = await showHexaBottomSheet<bool>(
      context: context,
      compact: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
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
