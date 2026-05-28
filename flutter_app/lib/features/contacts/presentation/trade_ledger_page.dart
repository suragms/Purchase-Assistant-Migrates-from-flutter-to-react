import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/broker_statement_pdf.dart';
import '../../../core/services/item_statement_pdf.dart';
import '../../../core/services/pdf_actions.dart';
import '../../../core/services/supplier_statement_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/utils/phone_launch.dart';
import '../../../core/widgets/focused_search_chrome.dart';
import '../../../core/utils/trade_purchase_commission.dart';
import '../../../core/utils/trade_purchase_rate_display.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import '../../../shared/widgets/trade_purchase_ledger_cards.dart';
import '../../purchase/providers/trade_purchase_detail_provider.dart';

enum TradeLedgerKind { supplier, broker, catalogItem }

DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

Widget _ledgerCatalogPartyBlock({
  required BuildContext context,
  required String label,
  required String? name,
  required String? phoneRaw,
}) {
  final nameT = name?.trim() ?? '';
  final phone = phoneRaw?.trim() ?? '';
  if (nameT.isEmpty && phone.isEmpty) return const SizedBox.shrink();
  final tt = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 6),
      Text(
        label,
        style: tt.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              nameT.isEmpty ? '—' : nameT,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (phone.isNotEmpty)
            IconButton(
              tooltip: 'Call',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.call_outlined, size: 20),
              onPressed: () => dialPhone(phone),
            ),
        ],
      ),
    ],
  );
}

/// PUR ledger for a supplier, broker, or catalog item (trade purchases only).
class TradeLedgerPage extends ConsumerStatefulWidget {
  const TradeLedgerPage({
    super.key,
    required this.kind,
    required this.entityId,
  });

  final TradeLedgerKind kind;
  final String entityId;

  @override
  ConsumerState<TradeLedgerPage> createState() => _TradeLedgerPageState();
}

class _TradeLedgerPageState extends ConsumerState<TradeLedgerPage> {
  bool _loading = true;
  String? _error;
  List<TradePurchase> _rows = const [];
  final _searchCtrl = TextEditingController();
  final _ledgerSearchFocus = FocusNode();

  late DateTime _to;
  late DateTime _from;
  String _dateChip = 'This Month';

  @override
  void initState() {
    super.initState();
    final n = _dOnly(DateTime.now());
    _to = n;
    _from = DateTime(n.year, n.month, 1);
    _searchCtrl.addListener(() => setState(() {}));
    _ledgerSearchFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ledgerSearchFocus.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        TradeLedgerKind.supplier => 'Supplier ledger',
        TradeLedgerKind.broker => 'Broker ledger',
        TradeLedgerKind.catalogItem => 'Item ledger',
      };

  List<TradePurchase> get _inDateRange {
    return [
      for (final p in _rows)
        if (!_dOnly(p.purchaseDate).isBefore(_from) &&
            !_dOnly(p.purchaseDate).isAfter(_to))
          p,
    ];
  }

  List<TradePurchase> get _visibleRows {
    final base = _inDateRange;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((p) {
      if (p.humanId.toLowerCase().contains(q)) return true;
      final inv = p.invoiceNumber?.toLowerCase() ?? '';
      if (inv.contains(q)) return true;
      final ds = DateFormat('dd MMM yyyy').format(p.purchaseDate).toLowerCase();
      if (ds.contains(q)) return true;
      final ds2 = DateFormat('MMMM').format(p.purchaseDate).toLowerCase();
      if (ds2.contains(q)) return true;
      final sup = p.supplierName?.toLowerCase() ?? '';
      if (sup.contains(q)) return true;
      for (final l in p.lines) {
        if (l.itemName.toLowerCase().contains(q)) return true;
      }
      return p.itemsSummary.toLowerCase().contains(q);
    }).toList();
  }

  void _applyDateChip(String label) {
    final n = _dOnly(DateTime.now());
    setState(() {
      _dateChip = label;
      _to = n;
      switch (label) {
        case 'This Month':
          _from = DateTime(n.year, n.month, 1);
        case '3 Months':
          _from = n.subtract(const Duration(days: 89));
        case '6 Months':
          _from = n.subtract(const Duration(days: 179));
        case 'All':
          _from = _dOnly(DateTime(2020));
        default:
          break;
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: _from.isAfter(_to) ? _to : _from,
      end: _to,
    );
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (!mounted || r == null) return;
    setState(() {
      _dateChip = 'Custom';
      _from = _dOnly(r.start);
      _to = _dOnly(r.end);
    });
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: 200,
            status: 'all',
            supplierId: widget.kind == TradeLedgerKind.supplier
                ? widget.entityId
                : null,
            brokerId:
                widget.kind == TradeLedgerKind.broker ? widget.entityId : null,
            catalogItemId: widget.kind == TradeLedgerKind.catalogItem
                ? widget.entityId
                : null,
          );
      if (!mounted) return;
      final parsed = <TradePurchase>[];
      for (final e in raw) {
        try {
          parsed.add(
            TradePurchase.fromJson(Map<String, dynamic>.from(e as Map)),
          );
        } catch (_) {}
      }
      parsed.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      setState(() {
        _rows = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(TradePurchase p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted')),
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is DioException
                ? friendlyApiError(e)
                : 'Could not delete. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _shareStatementPdf(List<TradePurchase> data) async {
    final session = ref.read(sessionProvider);
    if (session == null || data.isEmpty) return;
    final biz = ref.read(invoiceBusinessProfileProvider);
    try {
      PdfActionResult? result;
      if (widget.kind == TradeLedgerKind.supplier) {
        final first = data.first;
        result = await shareSupplierStatementPdf(
          business: biz,
          supplierName: first.supplierName ?? 'Supplier',
          supplierAddress: first.supplierAddress,
          supplierGst: first.supplierGst,
          supplierPhone: first.supplierPhone ?? first.supplierWhatsapp,
          purchases: data,
          fromDate: _from,
          toDate: _to,
        );
      } else if (widget.kind == TradeLedgerKind.broker) {
        final first = data.first;
        result = await shareBrokerStatementPdf(
          business: biz,
          brokerName: first.brokerName ?? 'Broker',
          brokerPhone: first.brokerPhone,
          purchases: data,
          fromDate: _from,
          toDate: _to,
        );
      } else if (widget.kind == TradeLedgerKind.catalogItem) {
        final itemAsync = ref.read(catalogItemDetailProvider(widget.entityId));
        final name = itemAsync.maybeWhen(
          data: (m) => m['name']?.toString() ?? 'Item',
          orElse: () => 'Item',
        );
        result = await shareItemStatementPdf(
          business: biz,
          itemName: name,
          purchases: data,
          fromDate: _from,
          toDate: _to,
        );
      }
      if (mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not create PDF. ${userFacingError(e)}')),
        );
      }
    }
  }

  Future<void> _shareBrokerStatementForChat(List<TradePurchase> data) async {
    final session = ref.read(sessionProvider);
    if (session == null || data.isEmpty) return;
    if (widget.kind != TradeLedgerKind.broker) return;
    final biz = ref.read(invoiceBusinessProfileProvider);
    final first = data.first;
    try {
      await shareBrokerStatementPdfForChat(
        business: biz,
        brokerName: first.brokerName ?? 'Broker',
        brokerPhone: first.brokerPhone,
        purchases: data,
        fromDate: _from,
        toDate: _to,
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share. ${userFacingError(e)}')),
        );
      }
    }
  }

  static String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  static double _profitForPurchase(TradePurchase p) {
    if (p.totalLineProfit != null) return p.totalLineProfit!;
    var s = 0.0;
    for (final l in p.lines) {
      final lp = l.lineProfit;
      if (lp != null) s += lp;
    }
    return s;
  }

  static void _addUnitQty(TradePurchaseLine l, Map<String, double> u) {
    final up = l.unit.toUpperCase();
    if (unitCountsAsBagFamily(l.unit)) {
      u['bag'] = (u['bag'] ?? 0) + l.qty;
    } else if (up.contains('BOX')) {
      u['box'] = (u['box'] ?? 0) + l.qty;
    } else if (up.contains('TIN')) {
      u['tin'] = (u['tin'] ?? 0) + l.qty;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev && mounted) {
        _load();
      }
    });

    final itemAsync = widget.kind == TradeLedgerKind.catalogItem
        ? ref.watch(catalogItemDetailProvider(widget.entityId))
        : null;

    final data = _visibleRows;
    final sumTotal = data.fold<double>(0, (s, p) => s + p.totalAmount);
    final sumDue = data.fold<double>(0, (s, p) => s + p.remaining);
    final sumProfit = data.fold<double>(0, (s, p) => s + _profitForPurchase(p));
    final units = <String, double>{};
    for (final p in data) {
      for (final l in p.lines) {
        if (widget.kind == TradeLedgerKind.catalogItem) {
          if (l.catalogItemId == widget.entityId) _addUnitQty(l, units);
        } else {
          _addUnitQty(l, units);
        }
      }
    }
    var commSum = 0.0;
    if (widget.kind == TradeLedgerKind.broker) {
      for (final p in data) {
        commSum += tradePurchaseCommissionInr(p);
      }
    }

    final firstInAll = _rows.isNotEmpty ? _rows.first : null;
    final catalogLead =
        widget.kind == TradeLedgerKind.catalogItem && data.isNotEmpty
            ? data.first
            : null;
    final entityTitle = switch (widget.kind) {
      TradeLedgerKind.supplier =>
        (firstInAll?.supplierName?.trim().isNotEmpty == true)
            ? firstInAll!.supplierName!
            : 'Supplier',
      TradeLedgerKind.broker =>
        (firstInAll?.brokerName?.trim().isNotEmpty == true)
            ? firstInAll!.brokerName!
            : 'Broker',
      TradeLedgerKind.catalogItem => itemAsync?.maybeWhen(
            data: (m) => m['name']?.toString() ?? 'Item',
            orElse: () => 'Item',
          ) ??
          'Item',
    };

    final supplierPhoneStrip = widget.kind == TradeLedgerKind.supplier
        ? (firstInAll?.supplierPhone ?? firstInAll?.supplierWhatsapp)
        : null;
    final brokerPhoneStrip =
        widget.kind == TradeLedgerKind.broker ? firstInAll?.brokerPhone : null;
    final addr = widget.kind == TradeLedgerKind.supplier
        ? firstInAll?.supplierAddress
        : null;
    final gst = widget.kind == TradeLedgerKind.supplier
        ? firstInAll?.supplierGst
        : null;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const chipTeal = Color(0xFF17A8A7);
    const chipText = Color(0xFF374151);
    final fmt = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: Text(_title, overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: [
          if (widget.kind == TradeLedgerKind.catalogItem)
            IconButton(
              tooltip: 'Item details',
              onPressed: () => context.push('/catalog/item/${widget.entityId}'),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (widget.kind == TradeLedgerKind.supplier ||
              widget.kind == TradeLedgerKind.broker ||
              widget.kind == TradeLedgerKind.catalogItem)
            IconButton(
              tooltip: 'Share statement PDF',
              onPressed: (_loading || data.isEmpty)
                  ? null
                  : () => _shareStatementPdf(data),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (widget.kind == TradeLedgerKind.broker)
            IconButton(
              tooltip: 'Share PDF (WhatsApp, etc.)',
              onPressed: (_loading || data.isEmpty)
                  ? null
                  : () => _shareBrokerStatementForChat(data),
              icon: const Icon(Icons.chat_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        focusNode: _ledgerSearchFocus,
                        decoration: const InputDecoration(
                          hintText:
                              'Search invoice, item, supplier, date (e.g. Apr)…',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          isDense: true,
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CollapsibleSearchChrome(
                        searchActive: _ledgerSearchFocus.hasFocus ||
                            _searchCtrl.text.trim().isNotEmpty,
                        chrome: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entityTitle,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if (widget.kind ==
                                            TradeLedgerKind.catalogItem &&
                                        itemAsync != null)
                                      itemAsync.when(
                                        data: (m) {
                                          final h = m['hsn_code']?.toString();
                                          if (h == null || h.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'HSN: $h',
                                              style: tt.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          );
                                        },
                                        loading: () => const SizedBox.shrink(),
                                        error: (_, __) =>
                                            const SizedBox.shrink(),
                                      ),
                                    if (widget.kind ==
                                            TradeLedgerKind.supplier &&
                                        supplierPhoneStrip != null &&
                                        supplierPhoneStrip
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () =>
                                            dialPhone(supplierPhoneStrip),
                                        child: Row(
                                          children: [
                                            Icon(Icons.call_outlined,
                                                size: 16, color: cs.primary),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                supplierPhoneStrip,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: tt.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (widget.kind == TradeLedgerKind.broker &&
                                        brokerPhoneStrip != null &&
                                        brokerPhoneStrip.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () =>
                                            dialPhone(brokerPhoneStrip),
                                        child: Row(
                                          children: [
                                            Icon(Icons.call_outlined,
                                                size: 16, color: cs.primary),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                brokerPhoneStrip,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                style: tt.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (widget.kind ==
                                            TradeLedgerKind.catalogItem &&
                                        catalogLead != null) ...[
                                      _ledgerCatalogPartyBlock(
                                        context: context,
                                        label: 'Supplier',
                                        name: catalogLead.supplierName,
                                        phoneRaw: catalogLead.supplierPhone ??
                                            catalogLead.supplierWhatsapp,
                                      ),
                                      _ledgerCatalogPartyBlock(
                                        context: context,
                                        label: 'Broker',
                                        name: catalogLead.brokerName,
                                        phoneRaw: catalogLead.brokerPhone,
                                      ),
                                    ],
                                    if (addr != null &&
                                        addr.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        addr,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (gst != null &&
                                        gst.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'GSTIN: $gst',
                                        style: tt.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      'Period: ${fmt.format(_from)} – ${fmt.format(_to)}',
                                      style: tt.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: chipTeal,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Summary',
                                      style: tt.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${data.length} purchase(s) in view · Bill total ${_inr(sumTotal.round())}',
                                      style: tt.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (units.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Units: '
                                        '${[
                                          if ((units['bag'] ?? 0) > 0)
                                            'Bags ${units['bag']!.toStringAsFixed(0)}',
                                          if ((units['box'] ?? 0) > 0)
                                            'Box ${units['box']!.toStringAsFixed(0)}',
                                          if ((units['tin'] ?? 0) > 0)
                                            'Tin ${units['tin']!.toStringAsFixed(0)}',
                                        ].join(' · ')}',
                                        style: tt.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (sumProfit.abs() > 0.0001) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Line profit (est.) ${_inr(sumProfit.round())}',
                                        style: tt.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F766E),
                                        ),
                                      ),
                                    ],
                                    if (widget.kind ==
                                        TradeLedgerKind.broker) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Commission (stored %) ${_inr(commSum.round())}',
                                        style: tt.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: HexaColors.brandPrimary,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Outstanding (unpaid balance) ${_inr(sumDue.round())}',
                                      style: tt.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: sumDue > 1
                                            ? HexaColors.warning
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final label in <String>[
                                  'This Month',
                                  '3 Months',
                                  '6 Months',
                                  'All',
                                  'Custom',
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: _dateChip == label
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: _dateChip == label
                                            ? Colors.white
                                            : chipText,
                                      ),
                                    ),
                                    selected: _dateChip == label,
                                    onSelected: (_) {
                                      if (label == 'Custom') {
                                        unawaited(_pickCustomRange());
                                      } else {
                                        _applyDateChip(label);
                                      }
                                    },
                                    selectedColor: chipTeal,
                                    backgroundColor: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    side: BorderSide.none,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (data.isEmpty)
                        HexaEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: _rows.isEmpty
                              ? 'No trade purchases yet'
                              : 'No matches',
                          subtitle: _rows.isEmpty
                              ? switch (widget.kind) {
                                  TradeLedgerKind.supplier =>
                                    'Record a purchase with this supplier as the party to see it here.',
                                  TradeLedgerKind.broker =>
                                    'Record a purchase with this broker attached to see it here.',
                                  TradeLedgerKind.catalogItem =>
                                    'No saved lines linked this catalog item in recent bills.',
                                }
                              : 'Try different words or widen the period.',
                          primaryActionLabel: 'New purchase',
                          onPrimaryAction: () => context.push('/purchase/new'),
                        )
                      else
                        ...data.map((p) => _LedgerPurchaseCard(
                              p: p,
                              cs: cs,
                              tt: tt,
                              kind: widget.kind,
                              onOpen: () => context.push(
                                '/purchase/detail/${p.id}',
                                extra: p,
                              ),
                              onDelete: () => _confirmDelete(p),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _LedgerPurchaseCard extends StatelessWidget {
  const _LedgerPurchaseCard({
    required this.p,
    required this.cs,
    required this.tt,
    required this.kind,
    required this.onOpen,
    required this.onDelete,
  });

  final TradePurchase p;
  final ColorScheme cs;
  final TextTheme tt;
  final TradeLedgerKind kind;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  static String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  @override
  Widget build(BuildContext context) {
    final st = p.statusEnum;
    final comm = tradePurchaseCommissionInr(p);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.humanId,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.yMMMd().format(p.purchaseDate),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _inr(p.totalAmount.round()),
                      textAlign: TextAlign.end,
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              if (kind == TradeLedgerKind.catalogItem &&
                  (p.supplierName ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.supplierName!,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 6),
              for (final ln in p.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            ln.itemName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (ctx) {
                              final kg = lineKgEstimate(ln);
                              final intel = <String, dynamic>{
                                'last_line_qty': ln.qty,
                                'last_line_unit': ln.unit,
                                'last_line_weight_kg': kg,
                                'kg_per_unit': ln.kgPerUnit,
                                'last_purchase_price':
                                    tradePurchaseLineDisplayPurchaseRate(ln),
                                'last_selling_rate':
                                    tradePurchaseLineDisplaySellingRate(ln),
                              };
                              final q = formatLineQtyWeightFromTradeLine(ln);
                              final r = tradeIntelRatePairLine(intel);
                              final lineAmt = reportLineAmountInr(ln);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (q.isNotEmpty)
                                    Text(
                                      q,
                                      style: tt.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  if (r.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      r,
                                      style: tt.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    'Line ${_inr(lineAmt.round())}',
                                    style: tt.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: st.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      st.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: st.color,
                      ),
                    ),
                  ),
                  if (kind == TradeLedgerKind.broker &&
                      p.commissionPercent != null &&
                      p.commissionPercent! > 0)
                    Text(
                      'Comm ${_inr(comm.round())}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  TextButton(
                    onPressed: onOpen,
                    child: const Text('Edit / View'),
                  ),
                  TextButton(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
