import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';

enum StockUpdateMode { physical, system }

/// Physical count vs system ledger qty — shared by scan + stock sheets.
class StockUpdateModeToggle extends StatelessWidget {
  const StockUpdateModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final StockUpdateMode mode;
  final ValueChanged<StockUpdateMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StockUpdateMode>(
      segments: const [
        ButtonSegment(
          value: StockUpdateMode.physical,
          label: Text('Physical', style: TextStyle(fontSize: 11)),
          icon: Icon(Icons.inventory_outlined, size: 16),
        ),
        ButtonSegment(
          value: StockUpdateMode.system,
          label: Text('System', style: TextStyle(fontSize: 11)),
          icon: Icon(Icons.memory_outlined, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return HexaColors.brandPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HexaColors.brandPrimary;
          }
          return HexaColors.brandPrimary.withValues(alpha: 0.08);
        }),
      ),
    );
  }
}

String stockUpdateModeHint(StockUpdateMode mode) => switch (mode) {
      StockUpdateMode.physical =>
        'Physical count — warehouse floor qty (may differ from system).',
      StockUpdateMode.system =>
        'System stock — ledger qty. Owner is notified when staff changes this.',
    };
