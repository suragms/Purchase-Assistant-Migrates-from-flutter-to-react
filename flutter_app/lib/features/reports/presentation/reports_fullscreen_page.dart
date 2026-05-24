import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/providers/app_period_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/warehouse_units_breakdown_line.dart';
import '../reports_bi_tab.dart';
import '../widgets/bi/reports_summary_card.dart';
import 'widgets/reports_breakdown_tab.dart';
import 'widgets/reports_period_bar.dart';

/// Owner reports — full viewport for ring, search, and breakdown lists.
class ReportsFullscreenPage extends ConsumerStatefulWidget {
  const ReportsFullscreenPage({
    super.key,
    required this.initialTab,
    required this.initialPresetLabel,
  });

  final ReportsBiTab initialTab;
  final String initialPresetLabel;

  @override
  ConsumerState<ReportsFullscreenPage> createState() =>
      _ReportsFullscreenPageState();
}

class _ReportsFullscreenPageState extends ConsumerState<ReportsFullscreenPage> {
  late ReportsBiTab _tab;
  late String _presetLabel;
  final _searchCtl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _presetLabel = widget.initialPresetLabel;
    _searchCtl.addListener(() {
      final q = _searchCtl.text;
      if (q != _search && mounted) setState(() => _search = q);
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _applyPreset(String label) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final range = switch (label) {
      'Today' => (from: today, to: today),
      'Week' => (
          from: today.subtract(const Duration(days: 6)),
          to: today,
        ),
      'Month' => (
          from: today.subtract(const Duration(days: 29)),
          to: today,
        ),
      'Year' => (from: DateTime(n.year, 1, 1), to: today),
      _ => ref.read(analyticsDateRangeProvider),
    };
    ref.read(analyticsDateRangeProvider.notifier).state = range;
    ref.read(appSelectedPeriodProvider.notifier).state = switch (label) {
      'Today' => AppPeriod.today,
      'Week' => AppPeriod.week,
      'Month' => AppPeriod.month,
      'Year' => AppPeriod.year,
      _ => AppPeriod.custom,
    };
    setState(() => _presetLabel = label);
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  void _syncHome() {
    final hp = ref.read(homePeriodProvider);
    ref.read(appSelectedPeriodProvider.notifier).state =
        appPeriodFromHomePeriod(hp);
    final custom = ref.read(homeCustomDateRangeProvider);
    final r = homePeriodRange(hp, now: DateTime.now(), custom: custom);
    final from = DateTime(r.start.year, r.start.month, r.start.day);
    final rawTo = r.end.subtract(const Duration(days: 1));
    final to = DateTime(rawTo.year, rawTo.month, rawTo.day);
    ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
    setState(() => _presetLabel = hp.label);
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  Future<void> _pickCustom() async {
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
    setState(() => _presetLabel = 'Custom');
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  String _searchHint() => switch (_tab) {
        ReportsBiTab.items => 'Search items…',
        ReportsBiTab.suppliers => 'Search suppliers…',
        ReportsBiTab.brokers => 'Search brokers…',
        ReportsBiTab.categories => 'Search categories…',
        ReportsBiTab.subcategories => 'Search subcategories…',
        _ => 'Search reports…',
      };

  @override
  Widget build(BuildContext context) {
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final agg = ref.watch(reportsAggregateProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Reports — full view'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: ReportsPeriodBar(
              selectedPreset: _presetLabel,
              compact: true,
              onPresetSelected: _applyPreset,
              onCustomRange: () => unawaited(_pickCustom()),
              onSyncHome: _syncHome,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: _searchHint(),
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: _searchCtl.clear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ReportsSummaryCard(
              totals: agg.totals,
              periodLabel: _presetLabel,
              rangeLabel: rangeFmt,
              purchaseCount: merged.length,
              itemCount: agg.itemsAll.length,
              supplierCount: agg.suppliers.length,
              subcategoryCount: 8,
              collapsed: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: WarehouseUnitsBreakdownLine(
              segments: warehouseUnitSegmentsFromTradeTotals(agg.totals),
              fontSize: 12,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in [
                    ReportsBiTab.categories,
                    ReportsBiTab.subcategories,
                    ReportsBiTab.items,
                    ReportsBiTab.suppliers,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          t.shortLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        selected: _tab == t,
                        onSelected: (_) => setState(() => _tab = t),
                        showCheckmark: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _tabBody(agg)),
        ],
      ),
    );
  }

  Widget _tabBody(TradeReportAgg agg) {
    switch (_tab) {
      case ReportsBiTab.categories:
        return ReportsBreakdownTab(
          subcategories: false,
          agg: agg,
          searchQuery: _search,
          expanded: true,
        );
      case ReportsBiTab.subcategories:
        return ReportsBreakdownTab(
          subcategories: true,
          agg: agg,
          searchQuery: _search,
          expanded: true,
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Full-screen ring view works on Categories and Subcat tabs.\n'
              'Select one of those above.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
        );
    }
  }
}
