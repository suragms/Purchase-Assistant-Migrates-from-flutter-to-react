import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';
import 'home_formatters.dart';

/// Dense 2×2 KPI strip: today/month spend + stock alerts (fixed calendar windows).
class HomeKpiStrip extends StatelessWidget {
  const HomeKpiStrip({
    super.key,
    required this.todayAsync,
    required this.monthAsync,
    required this.alertCountsAsync,
  });

  final AsyncValue<HomeDashboardData> todayAsync;
  final AsyncValue<HomeDashboardData> monthAsync;
  final AsyncValue<({int low, int critical})> alertCountsAsync;

  @override
  Widget build(BuildContext context) {
    final today = todayAsync.valueOrNull;
    final month = monthAsync.valueOrNull;
    final counts = alertCountsAsync.valueOrNull;
    final low = counts?.low ?? 0;
    final crit = counts?.critical ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.35,
      children: [
        _KpiTile(
          label: 'Today spend',
          value: todayAsync.isLoading ? '…' : homeInr(today?.totalPurchase ?? 0),
          subtitle: todayAsync.isLoading ? null : homeDashboardUnitsLine(today),
          onTap: () => context.go('/reports'),
        ),
        _KpiTile(
          label: 'Month spend',
          value: monthAsync.isLoading ? '…' : homeInr(month?.totalPurchase ?? 0),
          subtitle: monthAsync.isLoading ? null : homeDashboardUnitsLine(month),
          onTap: () => context.go('/reports'),
        ),
        _KpiTile(
          label: 'Low stock',
          value: alertCountsAsync.isLoading ? '…' : '$low items',
          tint: low > 0 ? const Color(0xFFE65100) : null,
          onTap: () => context.go('/stock'),
        ),
        _KpiTile(
          label: 'Critical',
          value: alertCountsAsync.isLoading ? '…' : '$crit items',
          tint: crit > 0 ? const Color(0xFFC62828) : null,
          onTap: () => context.go('/stock'),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    this.subtitle,
    this.tint,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: HexaDsType.labelCaps(context).copyWith(fontSize: 10),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HexaDsType.heading(16, color: tint ?? HexaColors.textBody),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                WarehouseUnitsSubtitleText(
                  subtitle: subtitle!,
                  fontSize: 10,
                  fallbackStyle:
                      HexaDsType.bodySm(context).copyWith(fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
