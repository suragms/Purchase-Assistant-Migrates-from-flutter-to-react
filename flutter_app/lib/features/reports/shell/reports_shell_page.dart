import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/app_period_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/reports_filtered_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/providers/reports_shell_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/router/shell_navigation.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../features/analytics/presentation/analytics_report_helpers.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../filters/reports_filter_sheet.dart';
import '../filters/reports_filter_state.dart';
import '../presentation/widgets/reports_period_bar.dart';
import '../reports_bi_tab.dart';
import '../tabs/reports_items_tab.dart';
import '../tabs/reports_overview_tab.dart';
import '../tabs/reports_purchases_tab.dart';
import '../tabs/reports_stock_tab.dart';
import 'reports_layout.dart';
import 'reports_primary_tabs.dart';
import 'reports_top_bar.dart';

typedef FullReportsPage = ReportsShellPage;

enum _DatePreset { today, week, month, quarter, year, custom }

String _presetLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Week',
      _DatePreset.month => 'Month',
      _DatePreset.quarter => 'Quarter',
      _DatePreset.year => 'Year',
      _DatePreset.custom => 'Custom',
    };

AppPeriod _appPeriodFromPreset(_DatePreset preset) => switch (preset) {
      _DatePreset.today => AppPeriod.today,
      _DatePreset.week => AppPeriod.week,
      _DatePreset.month => AppPeriod.month,
      _DatePreset.quarter => AppPeriod.quarter,
      _DatePreset.year => AppPeriod.year,
      _DatePreset.custom => AppPeriod.custom,
    };

String _searchHint(ReportsBiTab tab) => switch (tab) {
      ReportsBiTab.items => 'Search items…',
      ReportsBiTab.purchases => 'Search purchases…',
      ReportsBiTab.stock => 'Search item name…',
      _ => 'Search reports…',
    };

/// Reports analytics shell — ERP layout: top bar, 4 tabs, unified filters.
class ReportsShellPage extends ConsumerStatefulWidget {
  const ReportsShellPage({super.key, this.initialTab});

  final ReportsBiTab? initialTab;

  @override
  ConsumerState<ReportsShellPage> createState() => _ReportsShellPageState();
}

class _ReportsShellPageState extends ConsumerState<ReportsShellPage> {
  _DatePreset _preset = _DatePreset.month;
  ReportsBiTab _biTab = ReportsBiTab.overview;
  String? _syncedUrlTab;
  String? _stockHighlight;

  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _rangeInvalidateDebounce;
  Timer? _periodPresetDebounce;
  Timer? _stallTimer;
  bool _stallBanner = false;

  int _visibleCap = 40;
  bool _exportingCsv = false;
  bool _exportingPdf = false;
  ProviderSubscription<AppPeriod>? _homePeriodSub;

  @override
  void initState() {
    super.initState();
    _biTab = widget.initialTab ?? ReportsBiTab.overview;
    _searchCtl.text = ref.read(reportsFilterProvider).searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appPeriod = ref.read(appSelectedPeriodProvider);
      _DatePreset synced = switch (appPeriod) {
        AppPeriod.today => _DatePreset.today,
        AppPeriod.week => _DatePreset.week,
        AppPeriod.month => _DatePreset.month,
        AppPeriod.quarter => _DatePreset.quarter,
        AppPeriod.year => _DatePreset.year,
        AppPeriod.allTime => _DatePreset.year,
        AppPeriod.custom => _DatePreset.custom,
      };
      if (_preset != synced) setState(() => _preset = synced);
      _homePeriodSub?.close();
      _homePeriodSub = ref.listenManual(appSelectedPeriodProvider, (prev, next) {
        if (!mounted || prev == next) return;
        _syncReportsPresetFromAppPeriod(next);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    final raw = uri.queryParameters['tab'];
    if (raw != _syncedUrlTab) {
      _syncedUrlTab = raw;
      final tab = ReportsBiTabX.resolveFromQuery(raw);
      if (tab != _biTab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _biTab = tab);
          ref.read(reportsShellTabProvider.notifier).state = tab;
        });
      }
      final preset = ReportsBiTabX.legacyFilterPreset(raw);
      if (preset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _applyLegacyFilterPreset(preset);
        });
      }
    }
    final section = ReportsBiTabX.stockSectionFromQuery(
      uri.queryParameters['section'] ?? raw,
    );
    if (section != null && section != _stockHighlight) {
      _stockHighlight = section;
    }
  }

  void _applyLegacyFilterPreset(ReportsLegacyFilterPreset preset) {
    final n = ref.read(reportsFilterProvider.notifier);
    switch (preset) {
      case ReportsLegacyFilterPreset.usageOnly:
        n.apply(
          ref.read(reportsFilterProvider).copyWith(
                usage: ReportsUsageFilter.usageOnly,
              ),
        );
      case ReportsLegacyFilterPreset.supplierFocus:
      case ReportsLegacyFilterPreset.brokerFocus:
      case ReportsLegacyFilterPreset.categoryFocus:
      case ReportsLegacyFilterPreset.subcategoryFocus:
        break;
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchDebounce?.cancel();
    _rangeInvalidateDebounce?.cancel();
    _periodPresetDebounce?.cancel();
    _stallTimer?.cancel();
    _homePeriodSub?.close();
    super.dispose();
  }

  void _syncReportsPresetFromAppPeriod(AppPeriod appPeriod) {
    final synced = switch (appPeriod) {
      AppPeriod.today => _DatePreset.today,
      AppPeriod.week => _DatePreset.week,
      AppPeriod.month => _DatePreset.month,
      AppPeriod.quarter => _DatePreset.quarter,
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
      _DatePreset.quarter => (
          from: DateTime(n.year, n.month - ((n.month - 1) % 3), 1),
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(reportsFilterProvider.notifier).setSearch(value);
      setState(() => _visibleCap = 40);
    });
  }

  void _clearSearch() {
    _searchCtl.clear();
    ref.read(reportsFilterProvider.notifier).setSearch('');
    setState(() => _visibleCap = 40);
  }

  void _bumpInvalidate() => ref.invalidate(reportsPurchasesPayloadProvider);

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
    ref.read(appSelectedPeriodProvider.notifier).state = AppPeriod.custom;
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
      'Quarter' => _DatePreset.quarter,
      'Year' => _DatePreset.year,
      _ => _DatePreset.month,
    };
    _applyDatePreset(p);
  }

  void _applyDatePreset(_DatePreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week => (
          from: today.subtract(const Duration(days: 6)),
          to: today,
        ),
      _DatePreset.month => (
          from: today.subtract(const Duration(days: 29)),
          to: today,
        ),
      _DatePreset.quarter => (
          from: DateTime(n.year, n.month - ((n.month - 1) % 3), 1),
          to: today,
        ),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    ref.read(appSelectedPeriodProvider.notifier).state = _appPeriodFromPreset(p);
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
    final r = homePeriodRange(hp, now: DateTime.now(), custom: custom);
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

  void _selectBiTab(ReportsBiTab tab) {
    if (_biTab == tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _biTab = tab;
      _visibleCap = 40;
    });
    ref.read(reportsShellTabProvider.notifier).state = tab;
    _syncReportsUrlQuiet(tab);
  }

  void _syncReportsUrlQuiet(ReportsBiTab tab) {
    final raw = tab.queryValue;
    _syncedUrlTab = raw;
    final state = GoRouterState.of(context);
    if (state.uri.queryParameters['tab'] == raw) return;
    final params = Map<String, String>.from(state.uri.queryParameters);
    params['tab'] = raw;
    params.remove('section');
    final next = Uri(path: '/reports', queryParameters: params).toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (GoRouterState.of(context).uri.toString() != next) {
        context.replace(next);
      }
    });
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
    if (_stallBanner || _stallTimer != null) return;
    _stallTimer = Timer(const Duration(milliseconds: 1500), () {
      _stallTimer = null;
      if (mounted) setState(() => _stallBanner = true);
    });
  }

  Future<void> _exportCsv({
    required TradeReportAgg agg,
    required ({DateTime from, DateTime to}) range,
  }) async {
    if (_exportingCsv || _exportingPdf) return;
    setState(() => _exportingCsv = true);
    try {
      final df = DateFormat('yyyy-MM-dd');
      final filtered = ref.read(reportsFilteredDataProvider);
      final buf = StringBuffer()
        ..writeln(
          '# Harisree Reports — ${_biTab.queryValue} — '
          '${df.format(range.from)} to ${df.format(range.to)}',
        );
      if (_biTab == ReportsBiTab.purchases) {
        buf.writeln('supplier,bag_qty,bag_kg,amount_inr');
        for (final s in filtered.suppliers) {
          buf.writeln([
            analyticsCsvCell(s.name),
            analyticsCsvCell(formatStockQtyNumber(s.bagQty)),
            analyticsCsvCell(formatStockQtyNumber(s.bagKg)),
            analyticsCsvCell(s.amountInr.toStringAsFixed(0)),
          ].join(','));
        }
      } else {
        buf.writeln('name,kg,bags,boxes,tins,amount_inr,purchase_count');
        for (final r in filtered.items) {
          buf.writeln([
            analyticsCsvCell(r.name),
            analyticsCsvCell(formatStockQtyNumber(r.kg)),
            analyticsCsvCell(formatStockQtyNumber(r.bags)),
            analyticsCsvCell(formatStockQtyNumber(r.boxes)),
            analyticsCsvCell(formatStockQtyNumber(r.tins)),
            analyticsCsvCell(r.amountInr.toStringAsFixed(0)),
            analyticsCsvCell('${r.dealIds.length}'),
          ].join(','));
        }
      }
      await Share.share(buf.toString(), subject: 'Reports export');
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _shareStatementPdf(List<TradePurchase> purchases) async {
    if (_exportingPdf || purchases.isEmpty) return;
    final biz = ref.read(invoiceBusinessProfileProvider);
    final range = ref.read(analyticsDateRangeProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download report PDF?'),
        content: const Text('Generate purchase statement for current period.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Download')),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  void _openExportSheet(List<TradePurchase> merged) {
    showHexaBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Full report PDF'),
            onTap: () {
              Navigator.pop(context);
              unawaited(_shareStatementPdf(merged));
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export CSV'),
            onTap: () {
              Navigator.pop(context);
              final range = ref.read(analyticsDateRangeProvider);
              final agg = ref.read(reportsFilteredDataProvider).agg;
              unawaited(_exportCsv(agg: agg, range: range));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody({
    required TradeReportAgg aggAll,
    required ReportsFilteredData filtered,
    required List<TradePurchase> merged,
    required bool showSkeleton,
    required bool showEmpty,
    required bool hasFetchError,
    required AsyncValue<ReportsPurchasePayload> purchasesAsync,
    required Widget Function() emptyCard,
  }) {
    if (showSkeleton && merged.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hasFetchError && merged.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: HexaEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load report data',
          action: FilledButton(onPressed: _bumpInvalidate, child: const Text('Retry')),
        ),
      );
    }
    if (showEmpty && _biTab != ReportsBiTab.stock) return emptyCard();

    switch (_biTab) {
      case ReportsBiTab.overview:
        return ReportsOverviewTab(
          agg: aggAll,
          merged: merged,
          showSkeleton: showSkeleton,
          hasFetchError: hasFetchError,
          showEmpty: showEmpty,
          purchasesError: purchasesAsync.error,
          onRetry: _bumpInvalidate,
          onMatchHome: _syncRangeWithHome,
          onPickRange: () => unawaited(_pickCustomRange()),
        );
      case ReportsBiTab.items:
        final cap = _visibleCap < filtered.items.length
            ? _visibleCap
            : filtered.items.length;
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ReportsItemsTab(
            rows: filtered.items.take(cap).toList(),
            merged: merged,
            hasMore: cap < filtered.items.length,
            onLoadMore: () => setState(() => _visibleCap += 40),
            isLoading: showSkeleton,
          ),
        );
      case ReportsBiTab.purchases:
        final purchases = filtered.purchases;
        final cap = _visibleCap < purchases.length
            ? _visibleCap
            : purchases.length;
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: ReportsPurchasesTab(
            agg: filtered.agg,
            purchases: purchases.take(cap).toList(),
            merged: merged,
            hasMore: cap < purchases.length,
            onLoadMore: () => setState(() => _visibleCap += 20),
            isLoading: showSkeleton,
          ),
        );
      case ReportsBiTab.stock:
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: ReportsStockTab(highlightSection: _stockHighlight),
        );
    }
  }

  Widget _heroSpendCard(TradeReportAgg agg) {
    final spend = agg.totals.inr;
    final deals = agg.totals.deals;
    final tone = spend > 0 ? const Color(0xFF0E4F46) : HexaColors.textSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL SPEND THIS ${_presetLabel(_preset).toUpperCase()}',
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatRupee(spend, decimals: false),
            style: TextStyle(
              fontSize: 38,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            deals > 0 ? '$deals purchases in selected range' : 'No purchases in selected range',
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ReportsPurchasePayload>>(
      reportsPurchasesPayloadProvider,
      (prev, next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _armStallBanner(next.isLoading, ref.read(reportsPurchasesMergedProvider).isNotEmpty);
        });
      },
    );

    final purchasesAsync = ref.watch(reportsPurchasesPayloadProvider);
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final aggAll = ref.watch(reportsAggregateProvider);
    final filtered = ref.watch(reportsFilteredDataProvider);
    final filterCount = ref.watch(reportsFilterProvider).activeCount;
    final session = ref.watch(sessionProvider);
    final hasFetchError = purchasesAsync.hasError;
    final showSkeleton = !hasFetchError &&
        purchasesAsync.isLoading &&
        merged.isEmpty &&
        !_stallBanner;
    final showEmpty = !hasFetchError &&
        merged.isEmpty &&
        (!purchasesAsync.isLoading || _stallBanner);

    final homePath =
        session != null ? authenticatedHomePath(session) : '/home';

    Widget emptyCard() => HexaEmptyState(
          icon: Icons.analytics_outlined,
          title: 'No purchases in this period.',
          action: FilledButton.tonal(
            onPressed: _bumpInvalidate,
            child: const Text('Retry'),
          ),
        );

    final tabBody = _buildTabBody(
      aggAll: aggAll,
      filtered: filtered,
      merged: merged,
      showSkeleton: showSkeleton,
      showEmpty: showEmpty,
      hasFetchError: hasFetchError,
      purchasesAsync: purchasesAsync,
      emptyCard: emptyCard,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportsPeriodBar(
                selectedPreset: _presetLabel(_preset),
                onPresetSelected: _applyDatePresetFromLabel,
                onCustomRange: () => unawaited(_pickCustomRange()),
                onSyncHome: _syncRangeWithHome,
                compact: true,
              ),
              _heroSpendCard(aggAll),
              ReportsPrimaryTabs(
                selected: _biTab,
                onSelected: _selectBiTab,
              ),
              if (purchasesAsync.isLoading && merged.isNotEmpty)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(child: tabBody),
            ],
          ),
        ),
        if (context.isReportsDesktop)
          const SizedBox(width: 320, child: ReportsFilterDrawer()),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        popShellTabOrGoHome(context, ref, homePath: homePath);
      },
      child: Scaffold(
        backgroundColor: HexaColors.brandBackground,
        appBar: ReportsTopBar(
          onBack: () => popShellTabOrGoHome(context, ref, homePath: homePath),
          searchController: _searchCtl,
          searchHint: _searchHint(_biTab),
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
          onFilter: () => showReportsFilterPanel(context: context, ref: ref),
          filterCount: filterCount,
          onExport: () => _openExportSheet(merged),
          exporting: _exportingPdf || _exportingCsv,
        ),
        body: session == null
            ? const Center(child: Text('Sign in'))
            : SafeArea(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _bumpInvalidate();
                    await ref.read(reportsPurchasesPayloadProvider.future);
                  },
                  child: content,
                ),
              ),
      ),
    );
  }
}