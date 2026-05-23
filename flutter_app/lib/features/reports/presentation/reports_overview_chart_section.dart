import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../widgets/spend_ring_chart.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Overview: stat cards, category pie, supplier donut (server breakdown APIs).
class ReportsOverviewChartSection extends ConsumerWidget {
  const ReportsOverviewChartSection({
    super.key,
    required this.agg,
    required this.viewportHeight,
    required this.isLoadingInitial,
    this.loadFailed = false,
    this.loadError,
    required this.isEmpty,
    required this.canRetry,
    required this.onRetry,
    required this.onMatchHome,
    required this.onPickRange,
    this.hideTopStatRow = false,
  });

  final TradeReportAgg agg;
  final double viewportHeight;
  final bool isLoadingInitial;
  final bool loadFailed;
  final Object? loadError;
  final bool isEmpty;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onMatchHome;
  final VoidCallback onPickRange;
  /// When true, skip the duplicate Total / item-count strip (parent shows summary card).
  final bool hideTopStatRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxD = math.min(viewportHeight * 0.32, 200.0);
    final chartSize = math.min(maxD, MediaQuery.sizeOf(context).width * 0.42)
        .clamp(120.0, maxD);

    if (isLoadingInitial) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _shimmerBox(height: 72)),
                  const SizedBox(width: 8),
                  Expanded(child: _shimmerBox(height: 72)),
                ],
              ),
              const SizedBox(height: 12),
              _shimmerBox(height: chartSize),
            ],
          ),
        ),
      );
    }

    if (loadFailed) {
      final detail = loadError == null ? '' : userFacingError(loadError!);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Icon(Icons.cloud_off_rounded,
                  size: 48, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load report data',
              textAlign: TextAlign.center,
              style: HexaDsType.h3(context),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center, style: HexaDsType.bodySm(context)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canRetry ? onRetry : null,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: canRetry ? onMatchHome : null,
              child: const Text('Match Home period'),
            ),
          ],
        ),
      );
    }

    if (isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SpendRingChart(
                diameter: chartSize * 0.85,
                strokeWidth: 7,
                values: const [1],
                colors: const [Color(0xFFE2E8F0)],
                centerChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 30, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No purchases in selected range',
                      textAlign: TextAlign.center,
                      style: HexaDsType.bodyPrimary(context).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: canRetry ? onRetry : null, child: const Text('Retry')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: canRetry ? onPickRange : null, child: const Text('Change period')),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.pushNamed('purchase_scan'),
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: const Text('Scan purchase bill'),
            ),
          ],
        ),
      );
    }

    final t = agg.totals;
    final catsAsync = ref.watch(analyticsCategoriesTableProvider);
    final supsAsync = ref.watch(analyticsSuppliersTableProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hideTopStatRow) ...[
          Row(
            children: [
              Expanded(
                child: _OverviewStatCard(
                  label: 'Total',
                  value: _inr0(t.inr.round()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OverviewStatCard(
                  label: 'Purchased',
                  value: '${agg.itemsAll.length} items',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        catsAsync.when(
          loading: () => _chartPlaceholder(chartSize),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => _CategoryPieCard(rows: rows, size: chartSize),
        ),
        const SizedBox(height: 12),
        supsAsync.when(
          loading: () => _chartPlaceholder(chartSize),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => _SupplierDonutCard(
            rows: rows,
            diameter: chartSize,
            fallbackTotal: t.inr,
          ),
        ),
      ],
    );
  }

  static Widget _shimmerBox({required double height}) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      );

  static Widget _chartPlaceholder(double h) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: h,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HexaDsType.labelCaps(context)),
          const SizedBox(height: 4),
          Text(
            value,
            style: HexaDsType.h2(context).copyWith(
              fontWeight: FontWeight.w900,
              color: HexaColors.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPieCard extends StatelessWidget {
  const _CategoryPieCard({required this.rows, required this.size});

  final List<Map<String, dynamic>> rows;
  final double size;

  @override
  Widget build(BuildContext context) {
    final usable = rows
        .where((r) => coerceToDouble(r['total_purchase']) > 1e-9)
        .take(6)
        .toList();
    final total = usable.fold<double>(
      0,
      (s, r) => s + coerceToDouble(r['total_purchase']),
    );
    if (usable.isEmpty || total <= 0) return const SizedBox.shrink();

    final palette = HexaColors.chartPalette;
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < usable.length; i++) {
      final v = coerceToDouble(usable[i]['total_purchase']);
      final pct = (v / total) * 100;
      sections.add(
        PieChartSectionData(
          color: palette[i % palette.length],
          value: v,
          radius: size * 0.22,
          title: pct >= 12 ? '${pct.toStringAsFixed(0)}%' : '',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      );
    }

    return _ChartCard(
      title: 'Category breakdown',
      child: SizedBox(
        height: size,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 1.5,
                      centerSpaceRadius: size * 0.18,
                      sections: sections,
                      pieTouchData: PieTouchData(enabled: false),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _inr0(total),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${usable.length} categories',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: _LegendList(
                labels: [
                  for (final r in usable)
                    r['category_name']?.toString() ??
                        r['category']?.toString() ??
                        '—',
                ],
                values: [
                  for (final r in usable) _inr0(coerceToDouble(r['total_purchase'])),
                ],
                colors: [
                  for (var i = 0; i < usable.length; i++)
                    palette[i % palette.length],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierDonutCard extends StatelessWidget {
  const _SupplierDonutCard({
    required this.rows,
    required this.diameter,
    required this.fallbackTotal,
  });

  final List<Map<String, dynamic>> rows;
  final double diameter;
  final double fallbackTotal;

  @override
  Widget build(BuildContext context) {
    final usable = rows
        .where((r) => coerceToDouble(r['total_purchase']) > 1e-9)
        .take(6)
        .toList();
    if (usable.isEmpty) return const SizedBox.shrink();

    final values = [
      for (final r in usable) coerceToDouble(r['total_purchase']),
    ];
    final colors = [
      for (var i = 0; i < usable.length; i++)
        HexaColors.chartPalette[i % HexaColors.chartPalette.length],
    ];
    final total = values.fold<double>(0, (a, b) => a + b);

    return _ChartCard(
      title: 'Supplier share',
      child: Center(
        child: SpendRingChart(
          diameter: diameter,
          strokeWidth: math.max(8.0, diameter * 0.05),
          values: values,
          colors: colors,
          centerChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _inr0(total > 0 ? total : fallbackTotal),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${usable.length} suppliers',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: HexaDsType.h3(context)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _LegendList extends StatelessWidget {
  const _LegendList({
    required this.labels,
    required this.values,
    required this.colors,
  });

  final List<String> labels;
  final List<String> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.bodySm(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: HexaDsColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  values[i],
                  style: HexaDsType.bodySm(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
