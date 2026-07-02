import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/delivery_pipeline_provider.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/section_inline_error.dart';
import 'home_formatters.dart';
import 'home_recent_changes_section.dart' show HomeSectionSkeleton;

/// Owner home: delivery pipeline counts with filtered purchase deep links.
///
/// Placed after [HomeCriticalAlertsGrid] — not duplicated in the dashboard grid.
class HomeDeliveryPipelineCard extends ConsumerWidget {
  const HomeDeliveryPipelineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(deliveryPipelineProvider);

    return pipeline.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(HexaOp.cardPadding),
          child: HomeSectionSkeleton(rows: 2),
        ),
      ),
      error: (_, __) => Card(
        child: SectionInlineError(
          message: 'Could not load delivery pipeline',
          onRetry: () => ref.invalidate(deliveryPipelineProvider),
        ),
      ),
      data: (p) {
        final dispatched =
            coerceToInt(p['dispatched']) + coerceToInt(p['in_transit']);
        final arrived = coerceToInt(p['arrived']) +
            coerceToInt(p['staff_verifying']);
        final readyCommit =
            coerceToInt(p['staff_verified']) + coerceToInt(p['partial']);
        final pendingAmt = coerceToDouble(p['total_pending_amount']);

        if (dispatched == 0 &&
            arrived == 0 &&
            readyCommit == 0 &&
            pendingAmt < 0.01) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: HexaColors.brandPrimary.withValues(alpha: 0.22),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.go('/purchase?filter=pending_delivery'),
            child: Padding(
              padding: const EdgeInsets.all(20), // Increased internal padding to 20
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        color: HexaColors.brandPrimary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Delivery pipeline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18, // Section Title: 18 Bold
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 22),
                    ],
                  ),
                  const SizedBox(height: 8), // Spacing: 8
                  Text(
                    'Not yet in system stock until staff verify and commit',
                    style: TextStyle(
                      fontSize: 12, // Subtitle: 12
                      fontWeight: FontWeight.w600,
                      color: HexaColors.brandPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16), // Spacing: 16
                  if (dispatched > 0)
                    _line(
                      context,
                      Icons.local_shipping_outlined,
                      '$dispatched dispatched',
                      '/purchase?filter=delivery_dispatched',
                    ),
                  if (arrived > 0)
                    _line(
                      context,
                      Icons.inventory_2_outlined,
                      '$arrived at warehouse — verify now',
                      '/purchase?filter=delivery_arrived',
                      highlight: true,
                    ),
                  if (readyCommit > 0)
                    _line(
                      context,
                      Icons.verified_outlined,
                      '$readyCommit verified — commit to stock',
                      '/purchase?filter=delivery_commit',
                      highlight: true,
                    ),
                  if (pendingAmt >= 0.01) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Pending value · ${homeInr(pendingAmt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Tap a row or card for filtered purchases',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HexaColors.brandPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    IconData icon,
    String label,
    String route, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: highlight
                    ? const Color(0xFFE65100)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                    color: highlight
                        ? const Color(0xFFE65100)
                        : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
