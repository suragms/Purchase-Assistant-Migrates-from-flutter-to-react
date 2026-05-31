import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/snack.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/session.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/router/shell_navigation.dart';
import '../../../features/shell/shell_branch_provider.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/app_period_provider.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/navigation/open_trade_item_from_report.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/reports_provider.dart'
    show
        ReportsPurchasePayload,
        reportsPurchasesPayloadProvider,
        reportsAggregateProvider,
        reportsPurchasesMergedProvider;
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../features/analytics/presentation/analytics_report_helpers.dart';
import 'reports_full_list_page.dart';
import 'reports_item_tile.dart';
import 'operational_reports_section.dart';
import 'reports_overview_chart_section.dart';
import '../reporting/reports_item_metrics.dart';
import '../reports_bi_tab.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/reports_bi_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart'
    show stockVariancesTodayProvider;
import 'widgets/reports_breakdown_tab.dart';
import 'widgets/reports_insights_strip.dart';
import 'widgets/reports_movement_tab.dart';
import 'widgets/reports_period_bar.dart';
import 'widgets/reports_stock_intel_tab.dart';
import '../widgets/bi/reports_summary_card.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _matchHomePeriodButtonLabel(AppPeriod period) =>
    'Match Home · ${period.label}';

AppPeriod _appPeriodFromPreset(_DatePreset preset) => switch (preset) {
      _DatePreset.today => AppPeriod.today,
      _DatePreset.week => AppPeriod.week,
      _DatePreset.month => AppPeriod.month,
      _DatePreset.year => AppPeriod.year,
      _DatePreset.custom => AppPeriod.custom,
    };

String _qtyReadable(double q) => formatStockQtyNumber(q);

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

// Tab model: [ReportsBiTab] in ../reports_bi_tab.dart

enum ReportsPackFilter { all, bag, box, tin }

ReportPackKind? _packKind(ReportsPackFilter f) => switch (f) {
      ReportsPackFilter.all => null,
      ReportsPackFilter.bag => ReportPackKind.bag,
      ReportsPackFilter.box => ReportPackKind.box,
      ReportsPackFilter.tin => ReportPackKind.tin,
    };

typedef FullReportsPage = ReportsPage;

/// Purchase reports: full-viewport layout, compact rows, drill-down.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key, this.initialTab});

  /// Deep link / query param tab (`?tab=items`).
  final ReportsBiTab? initialTab;

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  _DatePreset _preset = _DatePreset.month;
  ReportsBiTab _biTab = ReportsBiTab.overview;
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
  bool _reportsSummaryCollapsed = true;
  ProviderSubscription<AppPeriod>? _homePeriodSub;

  @override
  void initState() {
    super.initState();
    _biTab = widget.initialTab ?? ReportsBiTab.overview;
    _searchCtl.addListener(_onSearchTyping);
    _reportsSearchFocus.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appPeriod = ref.read(appSelectedPeriodProvider);
      _DatePreset synced = switch (appPeriod) {
        AppPeriod.today => _DatePreset.today,
        AppPeriod.week => _DatePreset.week,
        AppPeriod.month => _DatePreset.month,
        AppPeriod.year => _DatePreset.year,
        AppPeriod.allTime => _DatePreset.year,
        AppPeriod.custom => _DatePreset.custom,
      };
      if (_preset != synced) {
        setState(() => _preset = synced);
      }
      _homePeriodSub?.close();
      _homePeriodSub = ref.listenManual(
        appSelectedPeriodProvider,
        (prev, next) {
          if (!mounted || prev == next) return;
          _syncReportsPresetFromAppPeriod(next);
        },
      );
    });
  }

  void _syncReportsPresetFromAppPeriod(AppPeriod appPeriod) {
    final synced = switch (appPeriod) {
      AppPeriod.today => _DatePreset.today,
      AppPeriod.week => _DatePreset.week,
      AppPeriod.month => _DatePreset.month,
      AppPeriod.year => _DatePreset.year,
      AppPeriod.allTime => _DatePreset.year,
      AppPeriod.custom => _DatePreset.custom,
    };
    if (_preset == synced) return;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (synced) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today,
        ),
      _DatePreset.month => (
          from: today.subtract(const Duration(days: 29)),
          to: today,
        ),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() {
      _preset = synced;
      _visibleCap = 40;
    });
    _scheduleReportsReloadForRange();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = ReportsBiTabX.fromQuery(
      GoRouterState.of(context).uri.queryParameters['tab'],
    );
    if (tab != null && tab != _biTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _biTab = tab);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialTab;
    if (next != null && next != oldWidget.initialTab) {
      _biTab = next;
    }
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
    _homePeriodSub?.close();
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

  void _applyDatePresetFromLabel(String label) {
    final p = switch (label) {
      'Today' => _DatePreset.today,
      'Week' => _DatePreset.week,
      'Month' => _DatePreset.month,
      'Year' => _DatePreset.year,
      _ => _DatePreset.month,
    };
    _applyDatePreset(p);
  }

  String _searchHintForTab(ReportsBiTab tab) => switch (tab) {
        ReportsBiTab.items => 'Search items…',
        ReportsBiTab.suppliers => 'Search suppliers…',
        ReportsBiTab.brokers => 'Search brokers…',
        ReportsBiTab.categories => 'Search categories…',
        ReportsBiTab.subcategories => 'Search subcategories…',
        ReportsBiTab.purchases => 'Search purchases…',
        _ => 'Search reports…',
      };

  void _applyDatePreset(_DatePreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today
        ),
      _DatePreset.month => (
          from: today.subtract(const Duration(days: 29)),
          to: today
        ),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    ref.read(appSelectedPeriodProvider.notifier).state =
        _appPeriodFromPreset(p);
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
    ref.read(appSelectedPeriodProvider.notifier).state =
        appPeriodFromHomePeriod(hp);
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
        HomePeriod.allTime => _DatePreset.year,
        HomePeriod.custom => _DatePreset.custom,
      };
      _visibleCap = 40;
    });
    _scheduleReportsReloadForRange();
  }

  ReportsFullListKind _fullListKind() {
    if (_biTab == ReportsBiTab.suppliers) return ReportsFullListKind.suppliers;
    if (_biTab == ReportsBiTab.brokers) return ReportsFullListKind.brokers;
    return switch (_packFilter) {
      ReportsPackFilter.all => ReportsFullListKind.itemsBag,
      ReportsPackFilter.bag => ReportsFullListKind.itemsBag,
      ReportsPackFilter.box => ReportsFullListKind.itemsBox,
      ReportsPackFilter.tin => ReportsFullListKind.itemsTin,
    };
  }

  TradeReportAgg _aggForList(
      TradeReportAgg aggAll, TradeReportAgg aggFiltered) {
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
        '# Harisree Warehouse — Reports — ${_biTab.queryValue} — '
        '${df.format(range.from)} to ${df.format(range.to)}',
      );

      switch (_biTab) {
        case ReportsBiTab.purchases:
        case ReportsBiTab.overview:
        case ReportsBiTab.categories:
        case ReportsBiTab.subcategories:
        case ReportsBiTab.slowMoving:
        case ReportsBiTab.deadStock:
        case ReportsBiTab.usage:
        case ReportsBiTab.stockMovement:
          if (mounted) {
            showTopSnack(context,
                'Switch to Items, Suppliers, or Brokers to export rows.');
          }
          return;
        case ReportsBiTab.items:
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
          break;
        case ReportsBiTab.suppliers:
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
          break;
        case ReportsBiTab.brokers:
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

  Widget _periodBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: ReportsPeriodBar(
        selectedPreset: _presetLabel(_preset),
        onPresetSelected: _applyDatePresetFromLabel,
        onCustomRange: () => unawaited(_pickCustomRange()),
        onSyncHome: _syncRangeWithHome,
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

  void _selectBiTab(ReportsBiTab tab) {
    HapticFeedback.selectionClick();
    setState(() {
      _biTab = tab;
      _visibleCap = 40;
    });
  }

  void _openMoreTabsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ReportsBiTabX.moreSheet)
              ListTile(
                title: Text(t.shortLabel),
                trailing: _biTab == t
                    ? Icon(Icons.check_rounded, color: HexaColors.brandPrimary)
                    : null,
                selected: _biTab == t,
                onTap: () {
                  Navigator.pop(ctx);
                  _selectBiTab(t);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _compactReportsTabs() {
    final tt = Theme.of(context).textTheme;
    Widget chip(ReportsBiTab tab, {IconData? icon}) {
      final sel = _biTab == tab;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(
            tab.shortLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: sel ? HexaColors.brandPrimary : HexaColors.textBody,
            ),
          ),
          selected: sel,
          onSelected: (_) => _selectBiTab(tab),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    final moreSelected =
        ReportsBiTabX.moreSheet.contains(_biTab) ? _biTab : null;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in ReportsBiTabX.primaryRow) chip(t),
              ],
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: ActionChip(
            label: Text(
              moreSelected?.shortLabel ?? 'More',
              style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            avatar: moreSelected != null
                ? Icon(Icons.check_rounded,
                    size: 16, color: HexaColors.brandPrimary)
                : null,
            onPressed: _openMoreTabsSheet,
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
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
              leading: const Icon(Icons.fullscreen_rounded),
              title: const Text('View PDF full screen'),
              subtitle: const Text('Open print preview in app'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_viewStatementPdfFullScreen(merged));
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_rows_rounded),
              title: const Text('Export CSV'),
              subtitle: const Text('Items, suppliers, or brokers'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _biTab = ReportsBiTab.items);
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
                goShellTab(
                  context,
                  ref,
                  branch: ShellBranch.stock,
                  location: '/stock',
                );
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

    switch (_biTab) {
      case ReportsBiTab.items:
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
        final filtered = q.isEmpty
            ? rows
            : rows.where((r) => r.name.toLowerCase().contains(q)).toList();
        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No lines in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap =
            _visibleCap < filtered.length ? _visibleCap : filtered.length;
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
              onTap: () => openCatalogItemFromReportRow(
                context,
                ref,
                {'item_name': r.name},
                tab: 'purchases',
              ),
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
                    agg:
                        _packFilter == ReportsPackFilter.all ? aggAll : aggList,
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

      case ReportsBiTab.purchases:
        final filteredPurchases = q.isEmpty
            ? merged
            : merged.where((p) {
                final hay = [
                  p.supplierName,
                  p.humanId,
                  p.invoiceNumber,
                ].whereType<String>().join(' ').toLowerCase();
                return hay.contains(q);
              }).toList();
        if (filteredPurchases.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No purchases in this period.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final purchaseCap = _visibleCap < filteredPurchases.length
            ? _visibleCap
            : filteredPurchases.length;
        final df = DateFormat('d MMM yyyy');
        final purchaseChildren = <Widget>[];
        for (var i = 0; i < purchaseCap; i++) {
          final p = filteredPurchases[i];
          purchaseChildren.add(
            ListTile(
              dense: true,
              title: Text(
                p.supplierName ?? p.humanId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${p.humanId} · ${df.format(p.purchaseDate)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '₹${p.totalAmount.round()}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () => context.push('/purchase/detail/${p.id}', extra: p),
            ),
          );
          if (i < purchaseCap - 1) {
            purchaseChildren.add(
              Divider(height: 1, color: HexaColors.brandBorder),
            );
          }
        }
        if (purchaseCap < filteredPurchases.length) {
          purchaseChildren.add(
            TextButton(
              onPressed: () =>
                  setState(() => _visibleCap = filteredPurchases.length),
              child: const Text('Show all'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: purchaseChildren,
        );

      case ReportsBiTab.suppliers:
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
          if (i < cap - 1) {
            ch.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
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
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: ch);

      case ReportsBiTab.brokers:
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
          ch.add(_supplierTile(
              b.name, 'Commission ${_inr0(b.commission.round())}'));
          if (i < cap - 1) {
            ch.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
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
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: ch);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _viewStatementPdfFullScreen(
      List<TradePurchase> purchases) async {
    if (_exportingPdf || _exportingCsv) return;
    final range = ref.read(analyticsDateRangeProvider);
    final biz = ref.read(invoiceBusinessProfileProvider);
    if (purchases.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nothing to export for this period.'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      final result = await layoutTradeStatementSsotPdf(
        business: biz,
        from: range.from,
        to: range.to,
        purchases: purchases,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open PDF. ${userFacingError(e)}'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Dismiss', onPressed: () {}),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
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
    final df = DateFormat('dd MMM yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download report PDF?'),
        content: Text(
          'This will generate a purchase statement for ${df.format(range.from)} to ${df.format(range.to)}.',
        ),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Download')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _exportingPdf = true);
    try {
      final result = await layoutTradeStatementSsotPdf(
        business: biz,
        from: range.from,
        to: range.to,
        purchases: purchases,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
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

  Widget _buildTabContent({
    required TradeReportAgg aggList,
    required TradeReportAgg aggAll,
    required List<TradePurchase> merged,
    required bool showSkeleton,
    required bool showEmpty,
    required bool hasFetchError,
    required AsyncValue<ReportsPurchasePayload> purchasesAsync,
    required Session? session,
    required Widget Function() emptyCard,
  }) {
    if (showSkeleton && merged.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hasFetchError && merged.isEmpty) {
      return _reportsFetchErrorCard(context, purchasesAsync.error);
    }
    if (showEmpty &&
        _biTab != ReportsBiTab.slowMoving &&
        _biTab != ReportsBiTab.deadStock) {
      return emptyCard();
    }

    switch (_biTab) {
      case ReportsBiTab.overview:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportsInsightsStrip(agg: aggAll),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: ReportsOverviewChartSection(
                  agg: aggAll,
                  viewportHeight: 280,
                  isLoadingInitial: showSkeleton,
                  loadFailed: hasFetchError && merged.isEmpty,
                  loadError: purchasesAsync.error,
                  isEmpty: showEmpty,
                  canRetry: true,
                  hideTopStatRow: true,
                  onRetry: _bumpInvalidate,
                  onMatchHome: _syncRangeWithHome,
                  onPickRange: () => unawaited(_pickCustomRange()),
                ),
              ),
              if (session != null && sessionCanSeeFinancials(session))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: OperationalReportsSection(),
                ),
            ],
          ),
        );
      case ReportsBiTab.categories:
        return ReportsBreakdownTab(
          subcategories: false,
          agg: aggAll,
          searchQuery: _debouncedQuery,
        );
      case ReportsBiTab.subcategories:
        return ReportsBreakdownTab(
          subcategories: true,
          agg: aggAll,
          searchQuery: _debouncedQuery,
        );
      case ReportsBiTab.slowMoving:
        return const ReportsStockIntelTab(dead: false);
      case ReportsBiTab.deadStock:
        return const ReportsStockIntelTab(dead: true);
      case ReportsBiTab.stockMovement:
        return const ReportsMovementTab();
      case ReportsBiTab.usage:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Daily usage logs live under Operations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.push('/operations/usage'),
                  child: const Text('Open usage log'),
                ),
              ],
            ),
          ),
        );
      case ReportsBiTab.items:
      case ReportsBiTab.purchases:
      case ReportsBiTab.suppliers:
      case ReportsBiTab.brokers:
        return RepaintBoundary(
          child: _listBody(aggList, aggAll, merged),
        );
    }
  }

  Widget _desktopKpiRow(
    BuildContext context, {
    required num totalSpent,
    required int purchaseCount,
    required int varianceCount,
    required VoidCallback? onExportPdf,
    required Future<void> Function()? onExportCsv,
  }) {
    Widget kpi(String title, String value, String subtitle) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: kpi(
                'Total spent',
                _inr0(totalSpent),
                'In selected period',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: kpi(
                'Purchases',
                '$purchaseCount',
                'Bills in period',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: kpi(
                'Stock variance',
                '$varianceCount',
                'Items with diff today',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onExportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Export PDF'),
            ),
            OutlinedButton.icon(
              onPressed: onExportCsv == null
                  ? null
                  : () => unawaited(onExportCsv()),
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ReportsPurchasePayload>>(
      reportsPurchasesPayloadProvider,
      (prev, next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final merged = ref.read(reportsPurchasesMergedProvider);
          _armStallBanner(next.isLoading, merged.isNotEmpty);
        });
      },
    );

    final purchasesAsync = ref.watch(reportsPurchasesPayloadProvider);
    final payload = purchasesAsync.valueOrNull;
    final liveErr = payload?.liveFetchError;
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final fromLive = payload?.fromLiveFetch ?? false;

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
      return HexaEmptyState(
        icon: Icons.analytics_outlined,
        title: msg.split('\n').first,
        subtitle: msg.contains('\n') ? msg.split('\n').skip(1).join('\n') : null,
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonal(
              onPressed: () => _bumpInvalidate(),
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _syncRangeWithHome,
              child: Text(_matchHomePeriodButtonLabel(
                  ref.watch(appSelectedPeriodProvider))),
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
      );
    }

    final returnBranch = ref.watch(shellReturnBranchProvider);
    final homePath = session != null
        ? authenticatedHomePath(session)
        : '/home';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        popShellTabOrGoHome(context, ref, homePath: homePath);
      },
      child: Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: returnBranch != null ? 'Back' : 'Home',
          icon: Icon(
            returnBranch != null
                ? Icons.arrow_back_rounded
                : Icons.home_outlined,
          ),
          onPressed: () => popShellTabOrGoHome(context, ref, homePath: homePath),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reports'),
            Text(
              'Period totals · drill down by category or item',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _openReportsPdfSheet(merged),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: merged.isEmpty
                ? null
                : () => unawaited(_shareStatementPdf(merged)),
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
              } else if (v == 'sales') {
                context.push('/reports/sales-comparison');
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
                value: 'sales',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows_rounded),
                  title: Text('Sales comparison'),
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
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        24 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
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
                                    Icon(Icons.sync,
                                        color: Colors.amber.shade900),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Updating…',
                                        style: TextStyle(
                                            color: Colors.amber.shade900),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Only show the "saved copy" banner once we *know* live fetch
                          // failed (i.e. provider completed with fromLiveFetch=false).
                          // While loading, we may temporarily be showing Hive-cached data.
                          if (purchasesAsync.hasValue &&
                              !fromLive &&
                              merged.isNotEmpty)
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
                                        liveErr == null ||
                                                liveErr.trim().isEmpty
                                            ? 'Offline or server unreachable — showing saved copy. Pull down or tap Retry.'
                                            : 'Live refresh failed — showing saved copy.\n$liveErr',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: HexaColors.textBody),
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
                          TextField(
                            controller: _searchCtl,
                            focusNode: _reportsSearchFocus,
                            onChanged: (_) => setState(() {}),
                            scrollPadding: const EdgeInsets.only(bottom: 280),
                            decoration: InputDecoration(
                              hintText: _searchHintForTab(_biTab),
                              isDense: true,
                              prefixIcon:
                                  const Icon(Icons.search_rounded, size: 20),
                              suffixIcon: _searchCtl.text.trim().isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded,
                                          size: 18),
                                      onPressed: _clearSearch,
                                    )
                                  : null,
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
                          _periodBar(),
                          if (context.isDesktopLayout) ...[
                            const SizedBox(height: 10),
                            _desktopKpiRow(
                              context,
                              totalSpent: aggAll.totals.inr,
                              purchaseCount: merged.length,
                              varianceCount: ref
                                      .watch(stockVariancesTodayProvider)
                                      .valueOrNull
                                      ?.length ??
                                  0,
                              onExportPdf: merged.isEmpty
                                  ? null
                                  : () => _openReportsPdfSheet(merged),
                              onExportCsv: merged.isEmpty
                                  ? null
                                  : () => _exportCsv(
                                        purchases: merged,
                                        agg: aggList,
                                        range: range,
                                      ),
                            ),
                          ],
                          Builder(
                            builder: (context) {
                              final subCount = ref
                                      .watch(analyticsTypesTableProvider)
                                      .valueOrNull
                                      ?.length ??
                                  0;
                              final comparison = ref
                                  .watch(reportsPeriodComparisonProvider)
                                  .valueOrNull;
                              String? compLine;
                              bool? compUp;
                              final pct = comparison?['purchase_change_pct'];
                              if (pct is num) {
                                compUp = pct > 0;
                                compLine = pct >= 0
                                    ? '+${pct.toStringAsFixed(0)}% vs prior period'
                                    : '${pct.toStringAsFixed(0)}% vs prior period';
                              }
                              return ReportsSummaryCard(
                                totals: aggAll.totals,
                                periodLabel: _presetLabel(_preset),
                                rangeLabel: rangeFmt,
                                purchaseCount: merged.length,
                                itemCount: aggAll.itemsAll.length,
                                supplierCount: aggAll.suppliers.length,
                                subcategoryCount: subCount,
                                comparisonLine: compLine,
                                comparisonTrendUp: compUp,
                                collapsed: _reportsSummaryCollapsed,
                                onToggleCollapse: () => setState(
                                  () => _reportsSummaryCollapsed =
                                      !_reportsSummaryCollapsed,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _compactReportsTabs(),
                          const SizedBox(height: 12),
                          if (_biTab == ReportsBiTab.items) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  const Text(
                                    'Group:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  for (final f in ReportsPackFilter.values)
                                    HexaAccessibleFilterChip(
                                      label: switch (f) {
                                        ReportsPackFilter.all => 'All',
                                        ReportsPackFilter.bag => 'Bags',
                                        ReportsPackFilter.box => 'Box',
                                        ReportsPackFilter.tin => 'Tin',
                                      },
                                      selected: _packFilter == f,
                                      onSelected: (_) => setState(() {
                                        _packFilter = f;
                                        _visibleCap = 40;
                                      }),
                                      compact: true,
                                    ),
                                  const Text(
                                    'Sort:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  HexaAccessibleFilterChip(
                                    label: 'Latest',
                                    selected:
                                        _itemSort == TradeReportItemSort.latest,
                                    onSelected: (_) => setState(() {
                                      _itemSort = TradeReportItemSort.latest;
                                    }),
                                    compact: true,
                                  ),
                                  HexaAccessibleFilterChip(
                                    label: 'High qty',
                                    selected: _itemSort ==
                                        TradeReportItemSort.highQty,
                                    onSelected: (_) => setState(() {
                                      _itemSort = TradeReportItemSort.highQty;
                                    }),
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ]),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildTabContent(
                        aggList: aggList,
                        aggAll: aggAll,
                        merged: merged,
                        showSkeleton: showSkeleton,
                        showEmpty: showEmpty,
                        hasFetchError: hasFetchError,
                        purchasesAsync: purchasesAsync,
                        session: session,
                        emptyCard: emptyCard,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
    );
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() {
      _debouncedQuery = '';
      _visibleCap = 40;
    });
  }
}
