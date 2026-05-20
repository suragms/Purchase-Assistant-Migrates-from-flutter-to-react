import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/snack.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/focused_search_chrome.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../features/analytics/presentation/analytics_report_helpers.dart';
import 'reports_full_list_page.dart';
import 'reports_item_tile.dart';
import 'reports_overview_chart_section.dart';
import 'reports_whatsapp_sheet.dart';
import '../reporting/reports_item_metrics.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _qtyReadable(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);

String _kgReadable(double kg) {
  if (kg < 1e-9) return '0';
  if ((kg - kg.roundToDouble()).abs() < 1e-6) return '${kg.round()}';
  return kg.toStringAsFixed(1);
}

enum _DatePreset { today, week, month, year, custom }

String _presetLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Week',
      _DatePreset.month => 'Month',
      _DatePreset.year => 'Year',
      _DatePreset.custom => 'Custom',
    };

enum ReportsMainTab { overview, items, suppliers, brokers }

enum ReportsPackFilter { all, bag, box, tin }

ReportPackKind? _packKind(ReportsPackFilter f) => switch (f) {
      ReportsPackFilter.all => null,
      ReportsPackFilter.bag => ReportPackKind.bag,
      ReportsPackFilter.box => ReportPackKind.box,
      ReportsPackFilter.tin => ReportPackKind.tin,
    };

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: HexaColors.textBody,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: HexaColors.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

typedef FullReportsPage = ReportsPage;

/// Purchase reports: full-viewport layout, compact rows, drill-down.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  _DatePreset _preset = _DatePreset.month;
  ReportsMainTab _mainTab = ReportsMainTab.overview;
  ReportsPackFilter _packFilter = ReportsPackFilter.all;
  TradeReportItemSort _itemSort = TradeReportItemSort.highQty;

  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _reportsSearchFocus = FocusNode();
  String _debouncedQuery = '';
  Timer? _searchDebounce;
  Timer? _rangeInvalidateDebounce;
  Timer? _periodPresetDebounce;
  Timer? _stallTimer;
  bool _stallBanner = false;

  int _visibleCap = 40;
  bool _exportingCsv = false;
  bool _exportingPdf = false;
  bool _reportsSummaryCollapsed = false;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchTyping);
    _reportsSearchFocus.addListener(() => setState(() {}));
  }

  void _onSearchTyping() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _debouncedQuery = _searchCtl.text;
        _visibleCap = 40;
        if (_debouncedQuery.trim().isNotEmpty) {
          _reportsSummaryCollapsed = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _searchCtl.removeListener(_onSearchTyping);
    _searchCtl.dispose();
    _reportsSearchFocus.dispose();
    _searchDebounce?.cancel();
    _rangeInvalidateDebounce?.cancel();
    _periodPresetDebounce?.cancel();
    _stallTimer?.cancel();
    super.dispose();
  }

  void _armStallBanner(bool loading, bool hasPurchases) {
    if (!loading || hasPurchases) {
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_stallBanner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _stallBanner = false);
        });
      }
      return;
    }
    if (_stallBanner) return;
    if (_stallTimer != null) return;
    _stallTimer = Timer(const Duration(milliseconds: 1500), () {
      _stallTimer = null;
      if (!mounted) return;
      setState(() => _stallBanner = true);
    });
  }

  void _bumpInvalidate() {
    // Reports must not stampede the whole app on tab switches / retries.
    // Only refresh the Reports purchase payload for the current range.
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  /// Range changes only need a fresh `/trade-purchases` slice — avoid invalidating the whole purchase workspace.
  void _scheduleReportsReloadForRange() {
    _rangeInvalidateDebounce?.cancel();
    _rangeInvalidateDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.invalidate(reportsPurchasesPayloadProvider);
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() {
      _preset = _DatePreset.custom;
      _visibleCap = 40;
    });
    _scheduleReportsReloadForRange();
  }

  void _applyDatePreset(_DatePreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week =>
        (from: today.subtract(const Duration(days: 6)), to: today),
      _DatePreset.month =>
        (from: today.subtract(const Duration(days: 29)), to: today),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() {
      _preset = p;
      _visibleCap = 40;
    });
    _periodPresetDebounce?.cancel();
    _periodPresetDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _bumpInvalidate();
    });
  }

  void _syncRangeWithHome() {
    final hp = ref.read(homePeriodProvider);
    final custom = ref.read(homeCustomDateRangeProvider);
    final r = homePeriodRange(
      hp,
      now: DateTime.now(),
      custom: custom,
    );
    final from = DateTime(r.start.year, r.start.month, r.start.day);
    final rawTo = r.end.subtract(const Duration(days: 1));
    final to = DateTime(rawTo.year, rawTo.month, rawTo.day);
    ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
    setState(() {
      _preset = switch (hp) {
        HomePeriod.today => _DatePreset.today,
        HomePeriod.week => _DatePreset.week,
        HomePeriod.month => _DatePreset.month,
        HomePeriod.year => _DatePreset.year,
        HomePeriod.custom => _DatePreset.custom,
      };
      _visibleCap = 40;
    });
    _scheduleReportsReloadForRange();
  }

  ReportsFullListKind _fullListKind() {
    if (_mainTab == ReportsMainTab.suppliers) return ReportsFullListKind.suppliers;
    if (_mainTab == ReportsMainTab.brokers) return ReportsFullListKind.brokers;
    return switch (_packFilter) {
      ReportsPackFilter.all => ReportsFullListKind.itemsBag,
      ReportsPackFilter.bag => ReportsFullListKind.itemsBag,
      ReportsPackFilter.box => ReportsFullListKind.itemsBox,
      ReportsPackFilter.tin => ReportsFullListKind.itemsTin,
    };
  }

  TradeReportAgg _aggForList(TradeReportAgg aggAll, TradeReportAgg aggFiltered) {
    if (_packFilter == ReportsPackFilter.all) return aggAll;
    return aggFiltered;
  }

  Future<void> _exportCsv({
    required List<TradePurchase> purchases,
    required TradeReportAgg agg,
    required ({DateTime from, DateTime to}) range,
  }) async {
    if (_exportingCsv || _exportingPdf) return;
    setState(() => _exportingCsv = true);
    try {
      final df = DateFormat('yyyy-MM-dd');
      final qf = _debouncedQuery.trim().toLowerCase();
      final buf = StringBuffer();
      buf.writeln(
        '# Purchase Assistant — Reports — ${_mainTab.name} — '
        '${df.format(range.from)} to ${df.format(range.to)}',
      );

      switch (_mainTab) {
        case ReportsMainTab.overview:
          if (mounted) {
            showTopSnack(context, 'Switch to Items, Suppliers, or Brokers to export rows.');
          }
          return;
        case ReportsMainTab.items:
          List<TradeReportItemRow> rows;
          if (_packFilter == ReportsPackFilter.all) {
            rows = sortTradeReportItemsAll(List.of(agg.itemsAll), _itemSort);
          } else {
            rows = switch (_packFilter) {
              ReportsPackFilter.bag => agg.itemsBag,
              ReportsPackFilter.box => agg.itemsBox,
              ReportsPackFilter.tin => agg.itemsTin,
              ReportsPackFilter.all => agg.itemsAll,
            };
          }
          final filtered = qf.isEmpty
              ? rows
              : rows.where((r) => r.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              showTopSnack(context, 'Nothing to export for this view.');
            }
            return;
          }
          buf.writeln('name,kg,bags,boxes,tins,amount_inr');
          for (final r in filtered) {
            buf.writeln([
              analyticsCsvCell(r.name),
              analyticsCsvCell(_kgReadable(r.kg)),
              analyticsCsvCell(_qtyReadable(r.bags)),
              analyticsCsvCell(_qtyReadable(r.boxes)),
              analyticsCsvCell(_qtyReadable(r.tins)),
              analyticsCsvCell(r.amountInr.toStringAsFixed(0)),
            ].join(','));
          }
        case ReportsMainTab.suppliers:
          final raw = agg.suppliers;
          final filtered = qf.isEmpty
              ? raw
              : raw.where((s) => s.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              showTopSnack(context, 'Nothing to export for this view.');
            }
            return;
          }
          buf.writeln('supplier,bag_qty,bag_kg');
          for (final s in filtered) {
            buf.writeln([
              analyticsCsvCell(s.name),
              analyticsCsvCell(_qtyReadable(s.bagQty)),
              analyticsCsvCell(_kgReadable(s.bagKg)),
            ].join(','));
          }
        case ReportsMainTab.brokers:
          final raw = agg.brokers;
          final filtered = qf.isEmpty
              ? raw
              : raw.where((b) => b.name.toLowerCase().contains(qf)).toList();
          if (filtered.isEmpty) {
            if (mounted) {
              showTopSnack(context, 'Nothing to export for this view.');
            }
            return;
          }
          buf.writeln('broker,commission_inr');
          for (final b in filtered) {
            buf.writeln([
              analyticsCsvCell(b.name),
              analyticsCsvCell(b.commission.toStringAsFixed(0)),
            ].join(','));
          }
      }

      await Share.share(
        buf.toString(),
        subject: 'Reports ${df.format(range.from)}–${df.format(range.to)}',
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Widget _summaryHeader(TradeReportTotals t, String rangeFmt) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PopupMenuButton<_DatePreset>(
                onSelected: (p) {
                  if (p == _DatePreset.custom) {
                    unawaited(_pickCustomRange());
                  } else {
                    _applyDatePreset(p);
                  }
                },
                itemBuilder: (ctx) => [
                  for (final p in <_DatePreset>[
                    _DatePreset.today,
                    _DatePreset.week,
                    _DatePreset.month,
                    _DatePreset.year,
                  ])
                    PopupMenuItem(value: p, child: Text(_presetLabel(p))),
                  const PopupMenuItem(
                    value: _DatePreset.custom,
                    child: Text('Custom range…'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _presetLabel(_preset),
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rangeFmt,
                  textAlign: TextAlign.end,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip:
                    _reportsSummaryCollapsed ? 'Show summary' : 'Hide summary',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => setState(() {
                  _reportsSummaryCollapsed = !_reportsSummaryCollapsed;
                }),
                icon: Icon(
                  _reportsSummaryCollapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  color: HexaColors.brandPrimary,
                ),
              ),
            ],
          ),
          if (!_reportsSummaryCollapsed) ...[
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TOTAL AMOUNT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: HexaColors.textBody,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _inr0(t.inr.round()),
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricTile(label: 'Total kg', value: _kgReadable(t.kg)),
                        _MetricTile(label: 'Total bags', value: _qtyReadable(t.bags)),
                        _MetricTile(label: 'Total boxes', value: _qtyReadable(t.boxes)),
                        _MetricTile(label: 'Total tins', value: _qtyReadable(t.tins)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 2),
          TextButton(
            onPressed: _syncRangeWithHome,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Match Home period'),
          ),
        ],
      ),
    );
  }

  Widget _overviewBody(TradeReportTotals t) {
    final tt = Theme.of(context).textTheme;
    final hasPack =
        t.kg > 1e-9 || t.bags > 1e-9 || t.boxes > 1e-9 || t.tins > 1e-9;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            hasPack
                ? 'Totals are in the card above (including per-item lines such as sugar when recorded). '
                    'Open Items for the full product list and search by name.'
                : 'No bag / box / tin lines in this period. '
                    'Check date range, pull to refresh, or confirm purchases use those units.',
            style: tt.bodySmall?.copyWith(color: HexaColors.textBody, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _searchAggregateCard(List<TradeReportItemRow> matches) {
    if (matches.isEmpty) return const SizedBox.shrink();
    var kg = 0.0;
    var bags = 0.0;
    var boxes = 0.0;
    var tins = 0.0;
    var inr = 0.0;
    for (final r in matches) {
      kg += r.kg;
      bags += r.bags;
      boxes += r.boxes;
      tins += r.tins;
      inr += r.amountInr;
    }
    final title = matches.length == 1
        ? matches.first.name.toUpperCase()
        : 'Matches (${matches.length})';
    final fake = TradeReportItemRow(key: '_agg', name: '');
    fake.kg = kg;
    fake.bags = bags;
    fake.boxes = boxes;
    fake.tins = tins;
    final qtyLine = reportQtySummaryBoldLine(fake);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: HexaColors.brandCard,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    )),
            if (qtyLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                qtyLine,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _inr0(inr.round()),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _totalsPackSummaryLine(TradeReportTotals t) {
    final parts = <String>[];
    if (t.bags > 1e-9) parts.add('${_qtyReadable(t.bags)} BAGS');
    if (t.boxes > 1e-9) parts.add('${_qtyReadable(t.boxes)} BOXES');
    if (t.tins > 1e-9) parts.add('${_qtyReadable(t.tins)} TINS');
    if (t.kg > 1e-9) parts.add('${_kgReadable(t.kg)} KG');
    return parts.join(' · ');
  }

  Widget _ringSummaryCard(
    TradeReportTotals t,
    String periodLabel,
    int purchaseCount,
    int itemCount,
    int supplierCount,
  ) {
    final tt = Theme.of(context).textTheme;
    final pack = _totalsPackSummaryLine(t);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _inr0(t.inr.round()),
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                ),
                if (pack.isNotEmpty)
                  Expanded(
                    child: Text(
                      pack,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: HexaColors.textBody,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              periodLabel,
              style: tt.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: HexaColors.textBody,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricTile(
                  label: 'Purchases',
                  value: '$purchaseCount',
                ),
                _MetricTile(
                  label: 'Items',
                  value: '$itemCount',
                ),
                _MetricTile(
                  label: 'Suppliers',
                  value: '$supplierCount',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactReportsTabs() {
    final tt = Theme.of(context).textTheme;
    Widget cell(ReportsMainTab tab, IconData icon, String shortLabel) {
      final sel = _mainTab == tab;
      return Expanded(
        child: Material(
          color: sel
              ? HexaColors.brandPrimary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _mainTab = tab;
                _visibleCap = 40;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: sel ? HexaColors.brandPrimary : HexaColors.textBody,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: sel ? HexaColors.brandPrimary : HexaColors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(ReportsMainTab.overview, Icons.donut_large_rounded, 'Ring'),
        cell(ReportsMainTab.items, Icons.inventory_2_outlined, 'Items'),
        cell(ReportsMainTab.suppliers, Icons.storefront_outlined, 'Supp'),
        cell(ReportsMainTab.brokers, Icons.handshake_outlined, 'Brokers'),
      ],
    );
  }

  void _openReportsPdfSheet(List<TradePurchase> merged) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Full report PDF'),
              subtitle: const Text('Statement for current date range'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_shareStatementPdf(merged));
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_rows_rounded),
              title: const Text('Export CSV'),
              subtitle: const Text('Items, suppliers, or brokers'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _mainTab = ReportsMainTab.items);
                final range = ref.read(analyticsDateRangeProvider);
                final mergedNow = ref.read(reportsPurchasesMergedProvider);
                final aggList = ref.read(reportsAggregateProvider);
                final aggForExport = _aggForList(aggList, aggList);
                unawaited(_exportCsv(
                  purchases: mergedNow,
                  agg: aggForExport,
                  range: range,
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: const Text('Supplier statement'),
              subtitle: const Text('Open Contacts → pick a supplier'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/contacts');
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Stock report'),
              subtitle: const Text('View stock levels and filters'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/stock');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _supplierTile(
    String name,
    String line2, {
    String? amountLine,
    String? lastDateLine,
  }) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: HexaColors.brandPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  line2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: HexaColors.textBody,
                        height: 1.15,
                      ),
                ),
                if (lastDateLine != null && lastDateLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    lastDateLine,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: HexaColors.textBody,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (amountLine != null && amountLine.isNotEmpty)
            Text(
              amountLine,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: HexaColors.brandPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _listBody(
    TradeReportAgg aggList,
    TradeReportAgg aggAll,
    List<TradePurchase> merged,
  ) {
    final q = _debouncedQuery.trim().toLowerCase();

    switch (_mainTab) {
      case ReportsMainTab.overview:
        return _overviewBody(aggAll.totals);
      case ReportsMainTab.items:
        List<TradeReportItemRow> rows;
        if (_packFilter == ReportsPackFilter.all) {
          rows = sortTradeReportItemsAll(List.of(aggAll.itemsAll), _itemSort);
        } else {
          final raw = switch (_packFilter) {
            ReportsPackFilter.bag => aggList.itemsBag,
            ReportsPackFilter.box => aggList.itemsBox,
            ReportsPackFilter.tin => aggList.itemsTin,
            ReportsPackFilter.all => aggAll.itemsAll,
          };
          rows = sortTradeReportItemsAll(List.of(raw), _itemSort);
        }
        final filtered =
            q.isEmpty ? rows : rows.where((r) => r.name.toLowerCase().contains(q)).toList();
        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No lines in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < filtered.length ? _visibleCap : filtered.length;
        final children = <Widget>[];
        if (q.isNotEmpty && filtered.length > 1) {
          children.add(_searchAggregateCard(filtered));
        }
        for (var i = 0; i < cap; i++) {
          final r = filtered[i];
          final rateLine = reportItemRateArrowLine(merged, r.key);
          children.add(
            ReportsItemTile(
              index: i + 1,
              row: r,
              rateLine: rateLine,
              onTap: () {
                final encK = Uri.encodeComponent(r.key);
                final encN = Uri.encodeComponent(r.name);
                context.push('/reports/item-detail?k=$encK&n=$encN');
              },
            ),
          );
          if (i < cap - 1) {
            children.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        if (cap < filtered.length) {
          children.add(
            TextButton(
              onPressed: () => setState(() => _visibleCap = filtered.length),
              child: const Text('Show all'),
            ),
          );
        }
        if (cap == filtered.length && filtered.length > 8) {
          children.add(
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (ctx) => ReportsFullListPage(
                    kind: _fullListKind(),
                    searchQuery: _debouncedQuery,
                    agg: _packFilter == ReportsPackFilter.all ? aggAll : aggList,
                  ),
                ),
              ),
              child: const Text('Full-screen list'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );

      case ReportsMainTab.suppliers:
        final all = q.isEmpty
            ? aggList.suppliers
            : aggList.suppliers
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No suppliers in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final ch = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final s = all[i];
          final last = s.lastPurchaseDate;
          ch.add(_supplierTile(
            s.name,
            '${_qtyReadable(s.bagQty)} bags · ${_kgReadable(s.bagKg)} kg · ${s.dealIds.length} deals',
            amountLine: _inr0(s.amountInr.round()),
            lastDateLine: last != null
                ? 'Last: ${DateFormat('d MMM yyyy').format(last)}'
                : null,
          ));
          if (i < cap - 1) ch.add(Divider(height: 1, color: HexaColors.brandBorder));
        }
        if (cap < all.length) {
          ch.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) => ReportsFullListPage(
                      kind: ReportsFullListKind.suppliers,
                      searchQuery: _debouncedQuery,
                      agg: aggList,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: Text('View full list (${all.length})'),
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: ch);

      case ReportsMainTab.brokers:
        final all = q.isEmpty
            ? aggList.brokers
            : aggList.brokers
                .where((b) => b.name.toLowerCase().contains(q))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No broker-tagged purchases in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final ch = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final b = all[i];
          ch.add(_supplierTile(b.name, 'Commission ${_inr0(b.commission.round())}'));
          if (i < cap - 1) ch.add(Divider(height: 1, color: HexaColors.brandBorder));
        }
        if (cap < all.length) {
          ch.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (ctx) => ReportsFullListPage(
                      kind: ReportsFullListKind.brokers,
                      searchQuery: _debouncedQuery,
                      agg: aggList,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: Text('View full list (${all.length})'),
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: ch);
    }
  }

  Future<void> _shareStatementPdf(List<TradePurchase> purchases) async {
    if (_exportingPdf || _exportingCsv) return;
    final range = ref.read(analyticsDateRangeProvider);
    final biz = ref.read(invoiceBusinessProfileProvider);
    if (purchases.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export for this period.')),
        );
      }
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      await layoutTradeStatementSsotPdf(
        business: biz,
        from: range.from,
        to: range.to,
        purchases: purchases,
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export PDF. ${userFacingError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Widget _reportsFetchErrorCard(BuildContext context, Object? err) {
    final detail = err == null ? '' : userFacingError(err);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: HexaColors.brandCard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              'Could not load report data',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HexaColors.textBody,
                  ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HexaColors.textBody,
                      height: 1.3,
                    ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _bumpInvalidate(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _openWhatsAppSheet(
    TradeReportAgg aggAll,
    DateTime from,
    DateTime to,
    List<TradePurchase> purchases,
  ) {
    final biz = ref.read(invoiceBusinessProfileProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ReportsWhatsAppSheet(
        agg: aggAll,
        from: from,
        to: to,
        business: biz,
        purchases: purchases,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(reportsPurchasesPayloadProvider);
    final liveErr = purchasesAsync.value?.liveFetchError;
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final fromLive = purchasesAsync.value?.fromLiveFetch ?? false;
    _armStallBanner(purchasesAsync.isLoading, merged.isNotEmpty);

    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';

    final aggAll = ref.watch(reportsAggregateProvider);
    final kind = _packKind(_packFilter);
    final aggFiltered = _packFilter == ReportsPackFilter.all
        ? aggAll
        : buildTradeReportAgg(merged, onlyKind: kind);
    final aggList = _aggForList(aggAll, aggFiltered);

    final session = ref.watch(sessionProvider);
    final hasFetchError = purchasesAsync.hasError;
    final showSkeleton = !hasFetchError &&
        purchasesAsync.isLoading &&
        merged.isEmpty &&
        !_stallBanner;
    final showEmpty = !hasFetchError &&
        merged.isEmpty &&
        (!purchasesAsync.isLoading || _stallBanner);

    Widget emptyCard() {
      final msg = (liveErr != null && liveErr.trim().isNotEmpty)
          ? 'Could not refresh live data.\n$liveErr'
          : 'No purchases in this period.';
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 10),
        color: HexaColors.brandCard,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.analytics_outlined,
                  size: 36, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                msg,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HexaColors.textBody,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _bumpInvalidate(),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _syncRangeWithHome,
                child: const Text('Match Home period'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => unawaited(_pickCustomRange()),
                child: const Text('Pick date range'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => context.pushNamed('purchase_scan'),
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Scan purchase bill'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.go('/purchase/new'),
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text('New purchase'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            final s = ref.read(sessionProvider);
            if (s != null) context.go(authenticatedHomePath(s));
          },
        ),
        title: const Text('Reports'),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'PDF & export',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _openReportsPdfSheet(merged),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pdf') {
                await _shareStatementPdf(merged);
              } else if (v == 'csv') {
                await _exportCsv(
                  purchases: merged,
                  agg: aggList,
                  range: range,
                );
              } else if (v == 'wa') {
                _openWhatsAppSheet(aggAll, range.from, range.to, merged);
              } else if (v == 'refresh') {
                _bumpInvalidate();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: _exportingPdf
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Export PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: _exportingCsv
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  title: const Text('Export CSV'),
                ),
              ),
              const PopupMenuItem(
                value: 'wa',
                child: ListTile(
                  leading: Icon(Icons.chat_outlined),
                  title: Text('WhatsApp summary'),
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Refresh data'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  _bumpInvalidate();
                  await ref.read(reportsPurchasesPayloadProvider.future);
                },
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    4,
                    12,
                    24 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  children: [
                    if (purchasesAsync.isLoading && merged.isNotEmpty)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_stallBanner &&
                        purchasesAsync.isLoading &&
                        merged.isEmpty)
                      Material(
                        color: Colors.amber.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Icon(Icons.sync, color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Updating…',
                                  style: TextStyle(color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Only show the "saved copy" banner once we *know* live fetch
                    // failed (i.e. provider completed with fromLiveFetch=false).
                    // While loading, we may temporarily be showing Hive-cached data.
                    if (purchasesAsync.hasValue && !fromLive && merged.isNotEmpty)
                      Material(
                        color: HexaColors.brandCard,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  size: 18, color: HexaColors.textBody),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  liveErr == null || liveErr.trim().isEmpty
                                      ? 'Offline or server unreachable — showing saved copy. Pull down or tap Retry.'
                                      : 'Live refresh failed — showing saved copy.\n$liveErr',
                                  style: TextStyle(
                                      fontSize: 12, color: HexaColors.textBody),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _bumpInvalidate(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_mainTab != ReportsMainTab.overview) ...[
                      TextField(
                        controller: _searchCtl,
                        focusNode: _reportsSearchFocus,
                        onChanged: (_) => setState(() {}),
                        scrollPadding: const EdgeInsets.only(bottom: 280),
                        decoration: InputDecoration(
                          hintText: _mainTab == ReportsMainTab.items
                              ? 'Search items…'
                              : 'Search…',
                          isDense: true,
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: HexaColors.brandCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: HexaColors.brandBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: HexaColors.brandBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    CollapsibleSearchChrome(
                      searchActive: _mainTab != ReportsMainTab.overview &&
                          (_reportsSearchFocus.hasFocus ||
                              _debouncedQuery.trim().isNotEmpty),
                      chrome: _summaryHeader(aggAll.totals, rangeFmt),
                    ),
                    const SizedBox(height: 8),
                    _compactReportsTabs(),
                    if (_mainTab == ReportsMainTab.items) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Text(
                                'Group:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: Color(0xFF333333),
                                ),
                              ),
                              const SizedBox(width: 6),
                              for (final f in ReportsPackFilter.values) ...[
                                ChoiceChip(
                                  label: Text(
                                    switch (f) {
                                      ReportsPackFilter.all => 'All',
                                      ReportsPackFilter.bag => 'Bags',
                                      ReportsPackFilter.box => 'Box',
                                      ReportsPackFilter.tin => 'Tin',
                                    },
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: _packFilter == f,
                                  onSelected: (_) => setState(() {
                                    _packFilter = f;
                                    _visibleCap = 40;
                                  }),
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const SizedBox(width: 6),
                              ],
                              const SizedBox(width: 10),
                              const Text(
                                'Sort:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: Color(0xFF333333),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text(
                                  'Latest',
                                  style: TextStyle(fontSize: 11),
                                ),
                                selected:
                                    _itemSort == TradeReportItemSort.latest,
                                onSelected: (_) => setState(() {
                                  _itemSort = TradeReportItemSort.latest;
                                }),
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              ChoiceChip(
                                label: const Text(
                                  'High qty',
                                  style: TextStyle(fontSize: 11),
                                ),
                                selected:
                                    _itemSort == TradeReportItemSort.highQty,
                                onSelected: (_) => setState(() {
                                  _itemSort = TradeReportItemSort.highQty;
                                }),
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_mainTab == ReportsMainTab.overview &&
                        !showSkeleton &&
                        !(hasFetchError && merged.isEmpty)) ...[
                      const SizedBox(height: 8),
                      _ringSummaryCard(
                        aggAll.totals,
                        '${_presetLabel(_preset)} · $rangeFmt',
                        merged.length,
                        aggAll.itemsAll.length,
                        aggAll.suppliers.length,
                      ),
                    ],
                    if (_mainTab == ReportsMainTab.overview) ...[
                      const SizedBox(height: 4),
                      ReportsOverviewChartSection(
                        agg: aggAll,
                        viewportHeight: MediaQuery.sizeOf(context).height,
                        isLoadingInitial: showSkeleton,
                        loadFailed: hasFetchError && merged.isEmpty,
                        loadError: purchasesAsync.error,
                        isEmpty: showEmpty,
                        canRetry: true,
                        hideTopStatRow: true,
                        onRetry: () {
                          _bumpInvalidate();
                        },
                        onMatchHome: _syncRangeWithHome,
                        onPickRange: () => unawaited(_pickCustomRange()),
                      ),
                    ] else ...[
                      if (showSkeleton)
                        const ListSkeleton(
                          rowCount: 5,
                          rowHeight: 72,
                          padding: EdgeInsets.fromLTRB(0, 0, 0, 24),
                        )
                      else if (hasFetchError && merged.isEmpty)
                        _reportsFetchErrorCard(context, purchasesAsync.error)
                      else if (showEmpty)
                        emptyCard()
                      else
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder:
                              (Widget? currentChild, List<Widget> previousChildren) {
                            return Stack(
                              fit: StackFit.passthrough,
                              alignment: Alignment.topCenter,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          child: RepaintBoundary(
                            key: ValueKey<ReportsMainTab>(_mainTab),
                            child: _listBody(aggList, aggAll, merged),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
