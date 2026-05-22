import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/stock_audit_providers.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Owner home: warehouse audit KPI pills.
class HomeStockAuditStrip extends ConsumerWidget {
  const HomeStockAuditStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(stockAuditKpisProvider);
    return kpis.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (k) {
        final audited = coerceToInt(k['items_audited_today']);
        final mismatch = coerceToInt(k['mismatch_lines_today']);
        final pending = coerceToInt(k['pending_approval_count']);
        if (audited == 0 && mismatch == 0 && pending == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (audited > 0)
                  _pill(context, 'Audited today: $audited', () {
                    context.push('/barcode/scan-history');
                  }),
                if (mismatch > 0) ...[
                  const SizedBox(width: 8),
                  _pill(
                    context,
                    'Mismatches: $mismatch',
                    () => context.push('/barcode/audit-session'),
                    fg: const Color(0xFFA32D2D),
                  ),
                ],
                if (pending > 0) ...[
                  const SizedBox(width: 8),
                  _pill(
                    context,
                    'Pending approval: $pending',
                    () => context.push('/barcode/scan-history'),
                    fg: HexaColors.brandPrimary,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    Color? fg,
  }) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg ?? HexaColors.textBody,
        ),
      ),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}
