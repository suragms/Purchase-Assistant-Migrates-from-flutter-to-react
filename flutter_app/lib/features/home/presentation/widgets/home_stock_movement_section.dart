import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/widgets/section_inline_error.dart';
import '../../../../shared/widgets/operational_ui.dart';
import '../../../stock/presentation/widgets/stock_today_feed.dart';
import 'home_formatters.dart';
import 'home_recent_changes_section.dart';

/// Period-filtered stock movement feed.
class HomeStockMovementSection extends ConsumerWidget {
  const HomeStockMovementSection({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(homePeriodProvider);
    final dash = ref.watch(homeDashboardDataProvider).snapshot.data;
    final audits = ref.watch(stockAuditPeriodProvider);
    final title = switch (period) {
      HomePeriod.today => "Today's stock movement",
      HomePeriod.week => "Week stock movement",
      HomePeriod.month => "Month stock movement",
      HomePeriod.year => "Year stock movement",
      HomePeriod.allTime => 'All-time stock movement',
      HomePeriod.custom => 'Stock movement',
    };

    Widget wrap({
      required Widget child,
      Widget? trailing,
    }) {
      if (embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing),
            child,
          ],
        );
      }
      return OperationalSection(
        title: title,
        dense: true,
        trailing: trailing,
        child: child,
      );
    }

    return audits.when(
      loading: () => wrap(child: const HomeSectionSkeleton(rows: 2)),
      error: (_, __) => wrap(
        child: SectionInlineError(
          message: 'Could not load stock movement',
          onRetry: () => ref.invalidate(stockAuditPeriodProvider),
        ),
      ),
      data: (rows) {
        final summary = _MovementSummary(
          purchased: dash.totalBags,
          adjusted: rows.length,
        );
        if (rows.isEmpty) {
          return wrap(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Text(
                    'No warehouse movement logged in this period',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          );
        }
        return wrap(
          trailing: TextButton(
            onPressed: () => context.push('/stock/today-feed'),
            child: const Text('View all', style: TextStyle(fontSize: 12)),
          ),
          child: Column(
            children: [
              summary,
              StockTodayFeed(rows: rows, maxRows: 5),
            ],
          ),
        );
      },
    );
  }
}

class _MovementSummary extends StatelessWidget {
  const _MovementSummary({required this.purchased, required this.adjusted});

  final double purchased;
  final int adjusted;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      if (purchased > 0) _cell('Purchased', '${homeFmtQty(purchased)} bags'),
      if (adjusted > 0) _cell('Adjusted', '$adjusted logs'),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(children: cells),
    );
  }

  Widget _cell(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
