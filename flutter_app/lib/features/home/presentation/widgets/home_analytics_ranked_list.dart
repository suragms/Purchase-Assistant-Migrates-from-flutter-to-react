import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';
import 'home_analytics_helpers.dart';
import 'home_formatters.dart';

/// Top ranked rows under the analytics ring.
class HomeAnalyticsRankedList extends StatelessWidget {
  const HomeAnalyticsRankedList({
    super.key,
    required this.slices,
    required this.tab,
    required this.dash,
    this.maxRows = 5,
  });

  final List<HomeAnalyticsSlice> slices;
  final HomeBreakdownTab tab;
  final HomeDashboardData dash;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final visible = slices.take(maxRows).toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          homeAnalyticsEmptyHint(tab, dash),
          style: HexaDsType.bodySm(context),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          _RankedRow(slice: visible[i]),
          if (i < visible.length - 1)
            const Divider(height: 1, indent: 18, endIndent: 0),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push(
              '/home/breakdown-more?tab=${homeBreakdownTabQuery(tab)}',
            ),
            child: const Text('View more', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.slice});

  final HomeAnalyticsSlice slice;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slice.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HexaDsType.listTitle(context).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (slice.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      WarehouseUnitsSubtitleText(
                        subtitle: slice.subtitle,
                        fontSize: 11,
                        fallbackStyle:
                            HexaDsType.bodySm(context).copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                homeInr(slice.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: HexaColors.brandPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
