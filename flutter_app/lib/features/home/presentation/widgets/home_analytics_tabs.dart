import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Category / Subcategory / Supplier / Items tabs inside analytics card.
class HomeAnalyticsTabs extends ConsumerWidget {
  const HomeAnalyticsTabs({super.key});

  static const _labels = ['Category', 'Subcategory', 'Supplier', 'Items'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeBreakdownTabProvider);
    final selected = tab.label;

    return Row(
      children: [
        for (final label in _labels) ...[
          Expanded(
            child: _TabChip(
              label: label,
              selected: selected == label,
              onTap: () {
                final match = HomeBreakdownTab.values.where((t) => t.label == label);
                if (match.isEmpty) return;
                ref.read(homeBreakdownTabProvider.notifier).state = match.first;
              },
            ),
          ),
          if (label != _labels.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? HexaColors.brandPrimary : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}
