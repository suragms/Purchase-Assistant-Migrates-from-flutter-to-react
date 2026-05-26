// Deprecated: shell Reports tab now uses FullReportsPage at `/reports`. File kept for reference.
import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/navigation/open_trade_item_from_report.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider, analyticsKpiProvider;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/analytics_overview_slice_error.dart';
import '../../../shared/widgets/app_settings_action.dart';
import 'analytics_report_helpers.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

class _TopBarsCard extends StatelessWidget {
  const _TopBarsCard({
    required this.title,
    required this.rows,
    required this.labelOf,
    required this.valueOf,
    required this.inr,
    this.color = HexaColors.primaryMid,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) labelOf;
  final num Function(Map<String, dynamic>) valueOf;
  final String Function(num n) inr;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final top = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
    final pick = top.take(4).toList();
    if (pick.isEmpty) return const SizedBox.shrink();
    final maxVal = pick
        .map((r) => valueOf(r).toDouble())
        .fold<double>(0, (p, c) => c > p ? c : p);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...pick.map((r) {
              final v = valueOf(r).toDouble();
              final p = maxVal <= 0 ? 0.0 : (v / maxVal).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            labelOf(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          inr(v),
                          style: tt.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 7,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SharePieCard extends StatelessWidget {
  const _SharePieCard({
    required this.title,
    required this.rows,
    required this.labelOf,
    required this.valueOf,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) labelOf;
  final num Function(Map<String, dynamic>) valueOf;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final usable = rows
        .where((r) => valueOf(r).toDouble() > 0)
        .take(6)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final total = usable.fold<double>(
      0,
      (sum, r) => sum + valueOf(r).toDouble(),
    );
    if (usable.isEmpty || total <= 0) return const SizedBox.shrink();
    final palette = HexaColors.chartPalette;
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < usable.length; i++) {
      final v = valueOf(usable[i]).toDouble();
      final pct = (v / total) * 100;
      sections.add(
        PieChartSectionData(
          color: palette[i % palette.length],
          value: v,
          radius: 34,
          title: pct >= 10 ? '${pct.toStringAsFixed(0)}%' : '',
          titleStyle: tt.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1.5,
                  centerSpaceRadius: 26,
                  sections: sections,
                  pieTouchData: PieTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankLineCard extends StatelessWidget {
  const _RankLineCard({
    required this.title,
    required this.rows,
    required this.valueOf,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final num Function(Map<String, dynamic>) valueOf;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final values = rows
        .map((r) => valueOf(r).toDouble())
        .where((v) => v > 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (values.length < 2) return const SizedBox.shrink();
    final top = values.take(8).toList();
    var minY = top.first;
    var maxY = top.first;
    final spots = <FlSpot>[];
    for (var i = 0; i < top.length; i++) {
      final y = top[i];
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      spots.add(FlSpot(i.toDouble(), y));
    }
    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minY: minY - span * 0.08,
                  maxY: maxY + span * 0.08,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: HexaColors.accentInfo,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: top.length <= 8,
                        getDotPainter: (a, b, c, d) => FlDotCirclePainter(
                          radius: 2.5,
                          color: HexaColors.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _filterQuery(
    List<Map<String, dynamic>> rows, String q, String field) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  return rows
      .where((r) => (r[field]?.toString() ?? '').toLowerCase().contains(t))
      .toList();
}

List<Map<String, dynamic>> _filterItemsRows(
    List<Map<String, dynamic>> rows, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  return rows.where((r) {
    for (final k in [
      'item_name',
      'category_name',
      'type_name',
      'supplier_name',
      'broker_name',
    ]) {
      if ((r[k]?.toString() ?? '').toLowerCase().contains(t)) return true;
    }
    final sim = r['similar_item_names'];
    if (sim is List) {
      for (final x in sim) {
        if (x.toString().toLowerCase().contains(t)) return true;
      }
    }
    return false;
  }).toList();
}

List<Map<String, dynamic>> _filterCategoryRows(
    List<Map<String, dynamic>> rows, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  return rows.where((r) {
    for (final k in [
      'category',
      'type_name',
      'best_item_name',
      'best_supplier_name',
    ]) {
      if ((r[k]?.toString() ?? '').toLowerCase().contains(t)) return true;
    }
    return false;
  }).toList();
}

DateTime _analyticsDayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Which preset matches the current range, or `custom`.
String _analyticsPresetId(({DateTime from, DateTime to}) range, DateTime now) {
  final today = _analyticsDayOnly(now);
  final fd = _analyticsDayOnly(range.from);
  final td = _analyticsDayOnly(range.to);
  final yest = today.subtract(const Duration(days: 1));
  if (fd == today && td == today) return 'today';
  if (fd == yest && td == yest) return 'yesterday';
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);
  final yearStart = DateTime(now.year, 1, 1);
  if (fd == weekStart && td == today) return 'this_week';
  if (fd == monthStart && td == today) return 'this_month';
  if (fd == yearStart && td == today) return 'this_year';
  if (fd == today.subtract(const Duration(days: 6)) && td == today) {
    return 'last_7';
  }
  if (fd == today.subtract(const Duration(days: 29)) && td == today) {
    return 'last_30';
  }
  final firstThis = DateTime(now.year, now.month, 1);
  final lastPrev = firstThis.subtract(const Duration(days: 1));
  final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
  if (fd == firstPrev && td == _analyticsDayOnly(lastPrev)) {
    return 'last_month';
  }
  return 'custom';
}

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  void _preset({required DateTime from, required DateTime to}) {
    ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
    _invalidateTables();
  }

  void _applyPresetId(String id, DateTime now) {
    final today = _analyticsDayOnly(now);
    switch (id) {
      case 'today':
        _preset(from: today, to: today);
        break;
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        _preset(from: y, to: y);
        break;
      case 'this_week':
        _preset(
            from: today.subtract(Duration(days: today.weekday - 1)), to: today);
        break;
      case 'this_month':
        _preset(from: DateTime(now.year, now.month, 1), to: today);
        break;
      case 'this_year':
        _preset(from: DateTime(now.year, 1, 1), to: today);
        break;
      case 'last_7':
        _preset(from: today.subtract(const Duration(days: 6)), to: today);
        break;
      case 'last_30':
        _preset(from: today.subtract(const Duration(days: 29)), to: today);
        break;
      case 'last_month':
        final firstThis = DateTime(now.year, now.month, 1);
        final lastPrev = firstThis.subtract(const Duration(days: 1));
        final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
        _preset(from: firstPrev, to: _analyticsDayOnly(lastPrev));
        break;
      default:
        break;
    }
  }

  void _invalidateTables() {
    ref.invalidate(analyticsKpiProvider);
    ref.invalidate(analyticsDailyProfitProvider);
    ref.invalidate(analyticsItemsTableProvider);
    ref.invalidate(analyticsCategoriesTableProvider);
    ref.invalidate(analyticsSuppliersTableProvider);
    ref.invalidate(analyticsBrokersTableProvider);
    ref.invalidate(analyticsBestSupplierInsightProvider);
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsDateRangeProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.yMMMd();

    final now = DateTime.now();
    final presetId = _analyticsPresetId(range, now);
    const presetLabels = <String, String>{
      'last_7': 'Last 7 days',
      'last_30': 'Last 30 days',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'this_week': 'This week',
      'this_month': 'This month',
      'this_year': 'This year',
      'last_month': 'Last month',
      'custom': 'Custom range',
    };

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: context.adaptiveAppBarBg,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Analytics',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
          ),
          actions: const [AppSettingsAction()],
          bottom: TabBar(
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: 'Items'),
              Tab(text: 'Categories'),
              Tab(text: 'Suppliers'),
              Tab(text: 'Brokers'),
              Tab(text: 'Summary'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButton<String>(
                    value: presetId,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final e in presetLabels.entries)
                        DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null || v == 'custom') return;
                      _applyPresetId(v, now);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(range.from)} – ${fmt.format(range.to)}',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: TabBarView(
                children: [
                  _ItemsTab(inr: _inr),
                  _CategoriesTab(inr: _inr),
                  _SuppliersTab(inr: _inr),
                  _BrokersTab(inr: _inr),
                  _OverviewTab(tt: tt, inr: _inr),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({
    required this.tt,
    required this.inr,
  });

  final TextTheme tt;
  final String Function(num n) inr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurf = Theme.of(context).colorScheme.onSurface;
    final kpi = ref.watch(analyticsKpiProvider);
    final cats = ref.watch(analyticsCategoriesTableProvider);
    final sup = ref.watch(analyticsSuppliersTableProvider);
    return kpi.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(analyticsKpiProvider);
          ref.invalidate(analyticsDailyProfitProvider);
          ref.invalidate(analyticsItemsTableProvider);
          ref.invalidate(analyticsCategoriesTableProvider);
          ref.invalidate(analyticsSuppliersTableProvider);
          ref.invalidate(analyticsBestSupplierInsightProvider);
        },
      ),
      data: (d) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsKpiProvider);
            ref.invalidate(analyticsDailyProfitProvider);
            ref.invalidate(analyticsItemsTableProvider);
            ref.invalidate(analyticsCategoriesTableProvider);
            ref.invalidate(analyticsSuppliersTableProvider);
            ref.invalidate(analyticsBestSupplierInsightProvider);
            await ref.read(analyticsKpiProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              Text('Charts & KPI mix',
                  style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: onSurf,
                      fontSize: 15)),
              const SizedBox(height: 8),
              _ProfitMixBar(
                totalPurchase: d.totalPurchase,
                totalProfit: d.totalProfit,
                purchaseCount: d.purchaseCount,
                totalQtyBase: d.totalQtyBase,
                inr: inr,
              ),
              const SizedBox(height: 12),
              sup.when(
                skipLoadingOnReload: true,
                loading: () => const SizedBox.shrink(),
                error: (_, __) => AnalyticsOverviewSliceError(
                    sectionLabel: 'Supplier performance',
                    onRetry: () =>
                        ref.invalidate(analyticsSuppliersTableProvider)),
                data: (rows) =>
                    _SupplierShareBars(rows: rows, tt: tt, inr: inr),
              ),
              const SizedBox(height: 10),
              cats.when(
                skipLoadingOnReload: true,
                loading: () => const SizedBox.shrink(),
                error: (_, __) => AnalyticsOverviewSliceError(
                    sectionLabel: 'Category split',
                    onRetry: () =>
                        ref.invalidate(analyticsCategoriesTableProvider)),
                data: (rows) =>
                    _CategoryShareBars(rows: rows, tt: tt, inr: inr),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfitMixBar extends StatelessWidget {
  const _ProfitMixBar({
    required this.totalPurchase,
    required this.totalProfit,
    required this.purchaseCount,
    required this.totalQtyBase,
    required this.inr,
  });

  final double totalPurchase;
  final double totalProfit;
  final int purchaseCount;
  final double totalQtyBase;
  final String Function(num) inr;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final purchase = totalPurchase <= 0 ? 0.0 : totalPurchase;
    final profit = totalProfit;
    final costLike = (purchase - profit);
    final c = costLike < 0 ? 0.0 : costLike;
    final p = profit < 0 ? 0.0 : profit;
    final denom = purchase > 0 ? purchase : (c + p > 0 ? c + p : 1.0);
    final flexC = ((c / denom) * 1000).round().clamp(0, 1000);
    final flexP = ((p / denom) * 1000).round().clamp(0, 1000);
    final fc = flexC <= 0 && flexP <= 0 ? 1 : flexC;
    final fp = flexC <= 0 && flexP <= 0 ? 0 : flexP;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buy value · retained · margin',
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: fc,
                    child: Container(color: HexaColors.chartLandingCost),
                  ),
                  Expanded(
                    flex: fp < 1 ? 1 : fp,
                    child: Container(color: HexaColors.profit),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${inr(purchase)} buy · ${inr(profit)} profit · '
            '$purchaseCount deals · ${totalQtyBase.toStringAsFixed(1)} qty',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierShareBars extends StatelessWidget {
  const _SupplierShareBars({
    required this.rows,
    required this.tt,
    required this.inr,
  });

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;
  final String Function(num) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        'No supplier-linked purchases in this range.',
        style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
      );
    }
    final top = rows.take(5).toList();
    final totalP = top.fold<double>(
      0,
      (a, r) => a + ((r['total_profit'] as num?)?.toDouble() ?? 0),
    );
    final denom = totalP > 0 ? totalP : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top suppliers (profit)',
          style: tt.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: HexaColors.primaryNavy,
          ),
        ),
        const SizedBox(height: 6),
        for (final r in top)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    r['supplier_name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (((r['total_profit'] as num?)?.toDouble() ?? 0) /
                              denom)
                          .clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: HexaColors.primaryLight,
                      color: HexaColors.accentInfo,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  inr((r['total_profit'] as num?)?.toDouble() ?? 0),
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryShareBars extends StatelessWidget {
  const _CategoryShareBars({
    required this.rows,
    required this.tt,
    required this.inr,
  });

  final List<Map<String, dynamic>> rows;
  final TextTheme tt;
  final String Function(num) inr;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final top = rows.take(5).toList();
    final totalP = top.fold<double>(
      0,
      (a, r) => a + ((r['total_profit'] as num?)?.toDouble() ?? 0),
    );
    final denom = totalP > 0 ? totalP : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories (profit)',
          style: tt.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: HexaColors.primaryNavy,
          ),
        ),
        const SizedBox(height: 6),
        for (final r in top)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    r['category']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (((r['total_profit'] as num?)?.toDouble() ?? 0) /
                              denom)
                          .clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: HexaColors.primaryLight,
                      color: HexaColors.brandTeal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  inr((r['total_profit'] as num?)?.toDouble() ?? 0),
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  static const _modes = [
    'name',
    'qty',
    'avg',
    'margin',
    'profit',
  ];
  static const _modeLabels = [
    'Name',
    'Qty',
    'Avg',
    'Margin',
    'Profit',
  ];
  int _sortColumnIndex = 4;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsItemsTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsItemsTableProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return HexaEmptyState(
            icon: Icons.insert_chart_outlined,
            title: 'No item data in this range',
            subtitle:
                'Try widening the date range, or add purchases so we can show rankings and trends.',
            primaryActionLabel: 'Add purchase',
            onPrimaryAction: () => context.push('/purchase/new'),
          );
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = sortedReportRows(
          rows,
          mode,
          _asc,
          (r) => (r['total_profit'] as num?) ?? 0,
        );
        final filtered = _filterItemsRows(sorted, _search.text);
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium
                    ?.copyWith(color: HexaColors.primaryNavy, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search item, category, supplier…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    FilterChip(
                      label: Text(_modeLabels[i]),
                      selected: _sortColumnIndex == i,
                      onSelected: (_) => setState(() {
                        if (_sortColumnIndex == i) {
                          _asc = !_asc;
                        } else {
                          _sortColumnIndex = i;
                          _asc = i == 0;
                        }
                      }),
                      selectedColor:
                          HexaColors.primaryLight.withValues(alpha: 0.95),
                      checkmarkColor: HexaColors.primaryDeep,
                      labelStyle:
                          tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} items',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => shareAnalyticsReportCsv(
                      title:
                          '${AppConfig.appName} Items ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Item',
                        'Category',
                        'Type',
                        'Supplier',
                        'Broker',
                        'Qty',
                        'Avg price',
                        'Profit',
                        'Margin %',
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['item_name']?.toString() ?? '',
                        (r) => r['category_name']?.toString() ?? '',
                        (r) => r['type_name']?.toString() ?? '',
                        (r) => r['supplier_name']?.toString() ?? '',
                        (r) => r['broker_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) =>
                            ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _TopBarsCard(
                title: 'Top items (profit)',
                rows: filtered,
                labelOf: (r) => r['item_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
                inr: widget.inr,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _SharePieCard(
                title: 'Item profit share',
                rows: filtered,
                labelOf: (r) => r['item_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _RankLineCard(
                title: 'Profit by item rank',
                rows: filtered,
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsItemsTableProvider);
                  await ref.read(analyticsItemsTableProvider.future);
                },
                child: filtered.isEmpty
                    ? ListView(
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          void openItem(Map<String, dynamic> r) {
                            unawaited(
                              openTradeItemFromReportRow(context, ref, r),
                            );
                          }

                          DataCell itemCell(
                              Map<String, dynamic> r, Widget child) {
                            return DataCell(
                              child,
                              onTap: () => openItem(r),
                            );
                          }

                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 88),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SizedBox(
                                width: math.max(760, constraints.maxWidth),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: const Color(0xFFE2E8F0),
                                    dataTableTheme: DataTableThemeData(
                                      headingRowHeight: 36,
                                      dataRowMinHeight: 40,
                                      dataRowMaxHeight: 52,
                                      horizontalMargin: 10,
                                      columnSpacing: 12,
                                      headingTextStyle: tt.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        color: HexaColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    border: const TableBorder(
                                      horizontalInside:
                                          BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('Item')),
                                      DataColumn(label: Text('Category')),
                                      DataColumn(label: Text('Type')),
                                      DataColumn(label: Text('Supplier')),
                                      DataColumn(label: Text('Broker')),
                                      DataColumn(
                                          label: Text('Qty'), numeric: true),
                                      DataColumn(
                                          label: Text('Avg'), numeric: true),
                                      DataColumn(
                                          label: Text('Profit'), numeric: true),
                                      DataColumn(
                                          label: Text('Margin'), numeric: true),
                                    ],
                                    rows: [
                                      for (final r in filtered)
                                        DataRow(
                                          cells: [
                                            itemCell(
                                              r,
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 3,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          analyticsMarginStripeColor(
                                                        (r['margin_pct']
                                                                as num?)
                                                            ?.toDouble(),
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              2),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      (r['item_name']?.toString() ??
                                                                  '')
                                                              .isEmpty
                                                          ? '—'
                                                          : r['item_name']
                                                              .toString(),
                                                      style: tt.bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                r['category_name']
                                                        ?.toString() ??
                                                    '—',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                r['type_name']?.toString() ??
                                                    '—',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                r['supplier_name']
                                                        ?.toString() ??
                                                    '—',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                r['broker_name']?.toString() ??
                                                    '—',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                ((r['total_qty'] as num?) ?? 0)
                                                    .toStringAsFixed(1),
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                widget.inr(
                                                  (r['avg_landing'] as num?)
                                                          ?.toDouble() ??
                                                      0,
                                                ),
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                widget.inr(
                                                  (r['total_profit'] as num?)
                                                          ?.toDouble() ??
                                                      0,
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                  color: ((r['total_profit']
                                                                  as num?) ??
                                                              0) >=
                                                          0
                                                      ? HexaColors.profit
                                                      : HexaColors.loss,
                                                ),
                                              ),
                                            ),
                                            itemCell(
                                              r,
                                              Text(
                                                '${((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                                                style: tt.bodySmall
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  static const _modes = ['profit', 'qty', 'trend'];
  static const _modeLabels = ['Profit', 'Volume', 'Growth'];
  int _sortColumnIndex = 0;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsCategoriesTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsCategoriesTableProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = sortedReportRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterCategoryRows(sorted, _search.text);
        final tt = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        final totalProfit = filtered.fold<double>(
          0,
          (a, r) => a + ((r['total_profit'] as num?)?.toDouble() ?? 0),
        );
        final totalQty = filtered.fold<double>(
          0,
          (a, r) => a + ((r['total_qty'] as num?)?.toDouble() ?? 0),
        );
        final top = filtered.isEmpty ? null : filtered.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium
                    ?.copyWith(color: HexaColors.primaryNavy, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search category, type, best item…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    FilterChip(
                      label: Text(_modeLabels[i]),
                      selected: _sortColumnIndex == i,
                      onSelected: (_) => setState(() {
                        if (_sortColumnIndex == i) {
                          _asc = !_asc;
                        } else {
                          _sortColumnIndex = i;
                          _asc = false;
                        }
                      }),
                      selectedColor:
                          HexaColors.primaryLight.withValues(alpha: 0.95),
                      checkmarkColor: HexaColors.primaryDeep,
                      labelStyle:
                          tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} categories',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => shareAnalyticsReportCsv(
                      title:
                          '${AppConfig.appName} Categories ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Category',
                        'Type',
                        'Total qty',
                        'Total profit',
                        'Best item',
                        'Best supplier',
                        'Lines',
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['category']?.toString() ?? '',
                        (r) => r['type_name']?.toString() ?? '',
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) => r['best_item_name']?.toString() ?? '',
                        (r) => r['best_supplier_name']?.toString() ?? '',
                        (r) => ((r['line_count'] as num?) ?? 0).toString(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.inr(totalProfit),
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'total profit',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Split by category · Volume ${totalQty.toStringAsFixed(0)}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (top != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Top: ${top['category'] ?? '—'} · ${widget.inr(((top['total_profit'] as num?) ?? 0).toDouble())}',
                        style: tt.labelSmall?.copyWith(
                          color: HexaColors.accentInfo,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsCategoriesTableProvider);
                  await ref.read(analyticsCategoriesTableProvider.future);
                },
                child: filtered.isEmpty
                    ? ListView(
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        children: [
                          const SizedBox(height: 28),
                          Center(
                              child: Text('Adjust search/filter',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final name = r['category']?.toString() ?? '—';
                          final bestItem =
                              r['best_item_name']?.toString() ?? '—';
                          final profit =
                              ((r['total_profit'] as num?) ?? 0).toDouble();
                          final qty =
                              ((r['total_qty'] as num?) ?? 0).toDouble();
                          final trend = r['trend']?.toString() ??
                              (profit >= 0 ? 'up' : 'down');
                          final contribution = totalProfit.abs() <= 0.01
                              ? 0.0
                              : (profit.abs() / totalProfit.abs())
                                  .clamp(0.0, 1.0);
                          final pctText =
                              '${(contribution * 100).toStringAsFixed(1)}%';
                          final profitColor =
                              profit >= 0 ? HexaColors.profit : HexaColors.loss;
                          return InkWell(
                            onTap: () => context.push(
                              '/contacts/category?name=${Uri.encodeComponent(name)}',
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tt.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        widget.inr(profit),
                                        style: tt.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: profitColor,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        trend == 'down'
                                            ? Icons.south_rounded
                                            : Icons.north_rounded,
                                        size: 16,
                                        color: trend == 'down'
                                            ? HexaColors.loss
                                            : HexaColors.profit,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Top item: $bestItem · $pctText contribution',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: contribution,
                                      minHeight: 6,
                                      backgroundColor:
                                          cs.surfaceContainerHighest,
                                      color: profitColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Qty ${qty.toStringAsFixed(1)} · ${trend == 'down' ? 'growth down' : 'growth up'}',
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuppliersTab extends ConsumerStatefulWidget {
  const _SuppliersTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends ConsumerState<_SuppliersTab> {
  static const _modes = [
    'name',
    'deals',
    'qty',
    'avg',
    'margin',
    'profit',
  ];
  static const _modeLabels = [
    'Name',
    'Deals',
    'Qty',
    'Avg ₹',
    'Margin',
    'Profit',
  ];
  int _sortColumnIndex = 5;
  bool _asc = false;
  final _search = TextEditingController();

  /// Loaded per supplier when a row expands (same date range as parent).
  final Map<String, List<Map<String, dynamic>>?> _supplierItemsCache = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSupplierItems(String sid) async {
    if (_supplierItemsCache[sid] != null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final range = ref.read(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    try {
      final rows = await ref.read(hexaApiProvider).analyticsSupplierItems(
            businessId: session.primaryBusiness.id,
            supplierId: sid,
            from: fmt.format(range.from),
            to: fmt.format(range.to),
          );
      if (!mounted) return;
      setState(() => _supplierItemsCache[sid] = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _supplierItemsCache[sid] = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsSuppliersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(analyticsSuppliersTableProvider);
          ref.invalidate(analyticsBestSupplierInsightProvider);
        },
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
              child: Text('No supplier-linked entries in this range'));
        }

        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = sortedReportRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterQuery(sorted, _search.text, 'supplier_name');
        final tt = Theme.of(context).textTheme;
        final insight = ref.watch(analyticsBestSupplierInsightProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            insight.when(
              data: (msg) {
                if (msg == null || msg.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    msg,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: HexaColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AnalyticsOverviewSliceError(
                  sectionLabel: 'Supplier insight',
                  onRetry: () =>
                      ref.invalidate(analyticsBestSupplierInsightProvider),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium
                    ?.copyWith(color: HexaColors.primaryNavy, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search suppliers…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    FilterChip(
                      label: Text(_modeLabels[i]),
                      selected: _sortColumnIndex == i,
                      onSelected: (_) => setState(() {
                        if (_sortColumnIndex == i) {
                          _asc = !_asc;
                        } else {
                          _sortColumnIndex = i;
                          _asc = i == 0;
                        }
                      }),
                      selectedColor:
                          HexaColors.primaryLight.withValues(alpha: 0.95),
                      checkmarkColor: HexaColors.primaryDeep,
                      labelStyle:
                          tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} suppliers',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => shareAnalyticsReportCsv(
                      title:
                          '${AppConfig.appName} Suppliers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Supplier',
                        'Deals',
                        'Total qty',
                        'Avg landing',
                        'Margin %',
                        'Profit'
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['supplier_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['total_qty'] as num?) ?? 0).toString(),
                        (r) => ((r['avg_landing'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) =>
                            ((r['margin_pct'] as num?) ?? 0).toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _TopBarsCard(
                title: 'Supplier comparison (profit)',
                rows: filtered,
                labelOf: (r) => r['supplier_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
                inr: widget.inr,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _SharePieCard(
                title: 'Supplier profit share',
                rows: filtered,
                labelOf: (r) => r['supplier_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _RankLineCard(
                title: 'Profit by supplier rank',
                rows: filtered,
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _supplierItemsCache.clear();
                  ref.invalidate(analyticsSuppliersTableProvider);
                  await ref.read(analyticsSuppliersTableProvider.future);
                },
                child: filtered.isEmpty
                    ? ListView(
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final sid = r['supplier_id']?.toString();
                          final m = (r['margin_pct'] as num?)?.toDouble() ?? 0;
                          final profit =
                              ((r['total_profit'] as num?) ?? 0).toDouble();
                          final deals = (r['deals'] as num?) ?? 0;
                          final tq = ((r['total_qty'] as num?) ?? 0).toDouble();
                          final name =
                              r['supplier_name']?.toString() ?? 'Supplier';
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                  splashColor: HexaColors.primaryLight
                                      .withValues(alpha: 0.3),
                                ),
                                child: ExpansionTile(
                                  key: ValueKey('sup_$sid'),
                                  onExpansionChanged: (expanded) {
                                    if (expanded &&
                                        sid != null &&
                                        sid.isNotEmpty) {
                                      unawaited(_loadSupplierItems(sid));
                                    }
                                  },
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 2),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(8, 0, 8, 10),
                                  leading: IconButton(
                                    tooltip: 'Supplier profile',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 36, minHeight: 36),
                                    icon: const Icon(Icons.open_in_new_rounded,
                                        size: 20, color: HexaColors.primaryMid),
                                    onPressed: sid == null || sid.isEmpty
                                        ? null
                                        : () => context.push('/supplier/$sid'),
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$deals deals · Qty ${tq.toStringAsFixed(1)} · '
                                    'Avg ${widget.inr(((r['avg_landing'] as num?) ?? 0).toDouble())} · '
                                    '${m.toStringAsFixed(1)}% · ${widget.inr(profit)}',
                                    maxLines: 2,
                                    style: tt.labelSmall?.copyWith(
                                      color: HexaColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  children: [
                                    if (sid == null || sid.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          'No supplier id',
                                          style: tt.bodySmall?.copyWith(
                                              color: HexaColors.textSecondary),
                                        ),
                                      )
                                    else
                                      Builder(
                                        builder: (ctx) {
                                          final items =
                                              _supplierItemsCache[sid];
                                          if (items == null) {
                                            return const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 12),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              ),
                                            );
                                          }
                                          if (items.isEmpty) {
                                            return Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(
                                                'No line items in range',
                                                style: tt.bodySmall?.copyWith(
                                                    color: HexaColors
                                                        .textSecondary),
                                              ),
                                            );
                                          }
                                          return Scrollbar(
                                            thumbVisibility: true,
                                            child: SizedBox(
                                              width: math.max(
                                                680,
                                                MediaQuery.sizeOf(ctx).width -
                                                    32,
                                              ),
                                              child: DataTable(
                                                headingRowHeight: 32,
                                                dataRowMinHeight: 36,
                                                dataRowMaxHeight: 44,
                                                horizontalMargin: 8,
                                                columnSpacing: 10,
                                                headingTextStyle:
                                                    tt.labelSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11,
                                                ),
                                                columns: const [
                                                  DataColumn(
                                                      label: Text('Item')),
                                                  DataColumn(
                                                      label: Text('Category')),
                                                  DataColumn(
                                                      label: Text('Type')),
                                                  DataColumn(
                                                      label: Text('Qty'),
                                                      numeric: true),
                                                  DataColumn(
                                                      label: Text('Avg'),
                                                      numeric: true),
                                                  DataColumn(
                                                      label: Text('Profit'),
                                                      numeric: true),
                                                  DataColumn(
                                                      label: Text('Margin'),
                                                      numeric: true),
                                                ],
                                                rows: [
                                                  for (final it in items)
                                                    DataRow(
                                                      cells: [
                                                        DataCell(Text(
                                                          it['item_name']
                                                                  ?.toString() ??
                                                              '—',
                                                          style: tt.bodySmall
                                                              ?.copyWith(
                                                                  fontSize: 12),
                                                        )),
                                                        DataCell(Text(
                                                          it['category']
                                                                  ?.toString() ??
                                                              '—',
                                                          style: tt.bodySmall
                                                              ?.copyWith(
                                                                  fontSize: 12),
                                                        )),
                                                        DataCell(Text(
                                                          it['type_name']
                                                                  ?.toString() ??
                                                              '—',
                                                          style: tt.bodySmall
                                                              ?.copyWith(
                                                                  fontSize: 12),
                                                        )),
                                                        DataCell(Text(
                                                          ((it['total_qty']
                                                                      as num?) ??
                                                                  0)
                                                              .toStringAsFixed(
                                                                  1),
                                                        )),
                                                        DataCell(Text(
                                                          widget.inr(
                                                            (it['avg_landing']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                0,
                                                          ),
                                                        )),
                                                        DataCell(Text(
                                                          widget.inr(
                                                            (it['total_profit']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                0,
                                                          ),
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 12,
                                                            color: ((it['total_profit']
                                                                            as num?) ??
                                                                        0) >=
                                                                    0
                                                                ? HexaColors
                                                                    .profit
                                                                : HexaColors
                                                                    .loss,
                                                          ),
                                                        )),
                                                        DataCell(Text(
                                                          '${((it['margin_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                                                        )),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BrokersTab extends ConsumerStatefulWidget {
  const _BrokersTab({required this.inr});

  final String Function(num n) inr;

  @override
  ConsumerState<_BrokersTab> createState() => _BrokersTabState();
}

class _BrokersTabState extends ConsumerState<_BrokersTab> {
  static const _modes = [
    'name',
    'deals',
    'commission',
    'commission_pct',
    'profit'
  ];
  static const _modeLabels = [
    'Name',
    'Deals',
    'Commission',
    'Comm %',
    'Profit'
  ];
  int _sortColumnIndex = 4;
  bool _asc = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsBrokersTableProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(analyticsBrokersTableProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
              child: Text('No broker-linked entries in this range'));
        }
        final mode = _modes[_sortColumnIndex.clamp(0, _modes.length - 1)];
        final sorted = sortedReportRows(
            rows, mode, _asc, (r) => (r['total_profit'] as num?) ?? 0);
        final filtered = _filterQuery(sorted, _search.text, 'broker_name');
        final tt = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: tt.bodyMedium
                    ?.copyWith(color: HexaColors.primaryNavy, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search brokers…',
                  hintStyle: TextStyle(
                      color: HexaColors.textSecondary.withValues(alpha: 0.85)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: HexaColors.primaryMid, size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide:
                          BorderSide(color: HexaColors.primaryMid, width: 1.5)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _modeLabels.length; i++)
                    FilterChip(
                      label: Text(_modeLabels[i]),
                      selected: _sortColumnIndex == i,
                      onSelected: (_) => setState(() {
                        if (_sortColumnIndex == i) {
                          _asc = !_asc;
                        } else {
                          _sortColumnIndex = i;
                          _asc = i == 0;
                        }
                      }),
                      selectedColor:
                          HexaColors.primaryLight.withValues(alpha: 0.95),
                      checkmarkColor: HexaColors.primaryDeep,
                      labelStyle:
                          tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Text('${filtered.length} brokers',
                      style: tt.labelMedium
                          ?.copyWith(color: HexaColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Export CSV',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => shareAnalyticsReportCsv(
                      title:
                          '${AppConfig.appName} Brokers ${fmt.format(range.from)}–${fmt.format(range.to)}',
                      headers: const [
                        'Broker',
                        'Deals',
                        'Commission',
                        'Comm % of profit',
                        'Profit impact',
                      ],
                      rows: filtered,
                      columns: [
                        (r) => r['broker_name']?.toString() ?? '',
                        (r) => ((r['deals'] as num?) ?? 0).toString(),
                        (r) => ((r['total_commission'] as num?) ?? 0)
                            .toStringAsFixed(2),
                        (r) => ((r['commission_pct_of_profit'] as num?) ?? 0)
                            .toStringAsFixed(1),
                        (r) => ((r['total_profit'] as num?) ?? 0)
                            .toStringAsFixed(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _TopBarsCard(
                title: 'Broker comparison (profit impact)',
                rows: filtered,
                labelOf: (r) => r['broker_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
                inr: widget.inr,
                color: HexaColors.accentAmber,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _SharePieCard(
                title: 'Broker profit share',
                rows: filtered,
                labelOf: (r) => r['broker_name']?.toString() ?? '—',
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _RankLineCard(
                title: 'Profit by broker rank',
                rows: filtered,
                valueOf: (r) => (r['total_profit'] as num?) ?? 0,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(analyticsBrokersTableProvider);
                  await ref.read(analyticsBrokersTableProvider.future);
                },
                child: filtered.isEmpty
                    ? ListView(
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        children: [
                          const SizedBox(height: 48),
                          Center(
                              child: Text('No matches',
                                  style: tt.bodyMedium?.copyWith(
                                      color: HexaColors.textSecondary))),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 88),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SizedBox(
                                width: math.max(620, constraints.maxWidth),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: const Color(0xFFE2E8F0),
                                    dataTableTheme: DataTableThemeData(
                                      headingRowHeight: 36,
                                      dataRowMinHeight: 40,
                                      dataRowMaxHeight: 48,
                                      horizontalMargin: 10,
                                      columnSpacing: 12,
                                      headingTextStyle: tt.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        color: HexaColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    border: const TableBorder(
                                      horizontalInside:
                                          BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('Broker')),
                                      DataColumn(
                                          label: Text('Deals'), numeric: true),
                                      DataColumn(
                                          label: Text('Commission'),
                                          numeric: true),
                                      DataColumn(
                                          label: Text('Comm %'), numeric: true),
                                      DataColumn(
                                          label: Text('Profit impact'),
                                          numeric: true),
                                    ],
                                    rows: [
                                      for (final r in filtered)
                                        DataRow(
                                          cells: [
                                            DataCell(
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.handshake_outlined,
                                                    size: 18,
                                                    color:
                                                        HexaColors.primaryMid,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      r['broker_name']
                                                              ?.toString() ??
                                                          '—',
                                                      style: tt.bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              onTap: () {
                                                final bid =
                                                    r['broker_id']?.toString();
                                                if (bid != null &&
                                                    bid.isNotEmpty) {
                                                  context.push('/broker/$bid');
                                                }
                                              },
                                            ),
                                            DataCell(Text(
                                              '${(r['deals'] as num?) ?? 0}',
                                              style: tt.bodySmall
                                                  ?.copyWith(fontSize: 12),
                                            )),
                                            DataCell(Text(
                                              widget.inr(
                                                ((r['total_commission']
                                                            as num?) ??
                                                        0)
                                                    .toDouble(),
                                              ),
                                              style: tt.bodySmall?.copyWith(
                                                fontSize: 12,
                                                color: HexaColors.chartOrange,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            )),
                                            DataCell(Text(
                                              '${((r['commission_pct_of_profit'] as num?) ?? 0).toStringAsFixed(1)}%',
                                              style: tt.bodySmall
                                                  ?.copyWith(fontSize: 12),
                                            )),
                                            DataCell(Text(
                                              widget.inr(
                                                ((r['total_profit'] as num?) ??
                                                        0)
                                                    .toDouble(),
                                              ),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                color: ((r['total_profit']
                                                                as num?) ??
                                                            0) >=
                                                        0
                                                    ? HexaColors.profit
                                                    : HexaColors.loss,
                                              ),
                                            )),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
