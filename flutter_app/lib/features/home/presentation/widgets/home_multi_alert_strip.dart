import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/warehouse_alerts_provider.dart';

/// Horizontal scrollable operational alert pills (owner home).
class HomeMultiAlertStrip extends ConsumerWidget {
  const HomeMultiAlertStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(warehouseAlertsProvider).valueOrNull;
    if (a == null || !a.hasAny) return const SizedBox.shrink();

    final pills = <({String label, Color color, VoidCallback onTap})>[];
    final lowTotal = a.lowStock + a.criticalStock;
    if (lowTotal > 0) {
      pills.add((
        label: '$lowTotal Reorder Needed',
        color: const Color(0xFFBA7517),
        onTap: () => context.go('/stock'),
      ));
    }
    if (a.missingUsageLogs > 0) {
      pills.add((
        label: '${a.missingUsageLogs} Usage Missing',
        color: const Color(0xFFBA7517),
        onTap: () => context.push('/operations/usage'),
      ));
    }
    if (a.missingBarcode > 0) {
      pills.add((
        label: '${a.missingBarcode} Missing barcode labels',
        color: const Color(0xFFA32D2D),
        onTap: () => context.push('/stock/missing-barcodes'),
      ));
    }
    if (a.pendingVerifications > 0) {
      pills.add((
        label: '${a.pendingVerifications} Stock Mismatch',
        color: const Color(0xFFA32D2D),
        onTap: () => context.go('/reports'),
      ));
    }
    if (a.evictionCount > 0) {
      pills.add((
        label: '${a.evictionCount} Eviction Needed',
        color: const Color(0xFFA32D2D),
        onTap: () => context.go('/stock'),
      ));
    }
    if (a.pendingDeliveries > 0) {
      pills.add((
        label: '${a.pendingDeliveries} Pending Delivery',
        color: const Color(0xFF3B6D11),
        onTap: () => context.go('/purchase'),
      ));
    }
    if (a.incompleteChecklist) {
      pills.add((
        label: 'Checklist Incomplete',
        color: const Color(0xFFBA7517),
        onTap: () => context.push('/operations/checklist'),
      ));
    }

    return SizedBox(
      height: HexaOp.chipHeight + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final p = pills[i];
          return _AlertPill(
            label: p.label,
            color: p.color,
            onTap: p.onTap,
          );
        },
      ),
    );
  }
}

class _AlertPill extends StatelessWidget {
  const _AlertPill({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: HexaOp.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
