import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/operations_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../presentation/widgets/reports_stock_intel_tab.dart';

/// Stock tab: fast / slow / dead sections (rolling ops window).
class ReportsStockTab extends ConsumerWidget {
  const ReportsStockTab({
    super.key,
    this.initialSection,
    required this.onSectionChanged,
  });

  final String? initialSection;
  final void Function(String section) onSectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationalReportsProvider);
    final section = initialSection ?? 'slow';
    return ops.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load stock intel')),
      data: (data) {
        final slow = (data['slow_moving'] as List?)?.length ?? 0;
        final dead = (data['dead_stock'] as List?)?.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Rolling warehouse intel — not filtered by report period',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _SectionChip(
                    label: 'Slow',
                    count: slow,
                    color: const Color(0xFFEA580C),
                    selected: section == 'slow',
                    onTap: () => onSectionChanged('slow'),
                  ),
                  _SectionChip(
                    label: 'Dead',
                    count: dead,
                    color: const Color(0xFFDC2626),
                    selected: section == 'dead',
                    onTap: () => onSectionChanged('dead'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReportsStockIntelTab(dead: section == 'dead'),
            ),
          ],
        );
      },
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: color.withValues(alpha: 0.15),
        checkmarkColor: color,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: selected ? color : HexaColors.textBody,
        ),
      ),
    );
  }
}
