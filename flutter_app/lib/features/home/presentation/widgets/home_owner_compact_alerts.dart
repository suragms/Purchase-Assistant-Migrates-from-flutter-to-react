import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/delivery_pipeline_provider.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/stock_providers.dart'
    show openingStockMissingProvider, stockStatusCountsProvider;

/// Owner home: priority cards (low stock + pending delivery first), then opening/out.
class HomeOwnerCompactAlerts extends ConsumerWidget {
  const HomeOwnerCompactAlerts({super.key});

  static const _critical = Color(0xFFDC2626);
  static const _warn = Color(0xFFF59E0B);
  static const _opening = Color(0xFFCA8A04);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(stockStatusCountsProvider).valueOrNull ?? const {};
    final low = coerceToInt(status['low']) + coerceToInt(status['critical']);
    final out = coerceToInt(status['out']);
    final openingN =
        coerceToInt(ref.watch(openingStockMissingProvider).valueOrNull?['missing_count']);
    final pipeline = ref.watch(deliveryPipelineProvider).valueOrNull;
    var pending = deliveryPipelinePendingCount(pipeline);
    if (pending == 0) {
      pending = ref.watch(homeDashboardDataProvider).snapshot.data.pendingDeliveryCount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Needs attention', style: HexaOp.cardTitle(context)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PriorityCard(
                label: 'Low stock',
                count: low,
                accent: _warn,
                onTap: () => context.push('/stock/low-stock'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PriorityCard(
                label: 'Pending delivery',
                count: pending,
                accent: _critical,
                filled: pending > 0,
                onTap: () => context.go('/purchase'),
              ),
            ),
          ],
        ),
        if (openingN > 0 || out > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (openingN > 0)
                Expanded(
                  child: _SecondaryChip(
                    label: 'Opening stock',
                    count: openingN,
                    accent: _opening,
                    onTap: () => context.push('/stock/opening-setup'),
                  ),
                ),
              if (openingN > 0 && out > 0) const SizedBox(width: 8),
              if (out > 0)
                Expanded(
                  child: _SecondaryChip(
                    label: 'Out of stock',
                    count: out,
                    accent: _critical,
                    onTap: () => context.go('/stock?status=out'),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.label,
    required this.count,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? accent.withValues(alpha: 0.1) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: filled ? 0.7 : 0.45),
              width: filled ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryChip extends StatelessWidget {
  const _SecondaryChip({
    required this.label,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
