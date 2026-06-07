import 'package:flutter/material.dart';

import '../../core/unit_engine/stock_tracking_profile.dart';
import '../../core/utils/unit_utils.dart';

/// Packaging type picker for catalog create/edit.
class PackagingTypeSelector extends StatelessWidget {
  const PackagingTypeSelector({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.suggestedMode,
    this.weightController,
    this.weightPerTinController,
    this.weightError,
    this.tinError,
    this.itemNameForAutofill,
    this.compactLayout = false,
  });

  void _autofillWeightFromName(String mode) {
    if (weightController == null || itemNameForAutofill == null) return;
    if (mode != StockTrackingMode.wholesaleBag &&
        mode != StockTrackingMode.retailPacket) {
      return;
    }
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*KG\b', caseSensitive: false)
        .firstMatch(itemNameForAutofill!);
    if (m != null && weightController!.text.trim().isEmpty) {
      weightController!.text = m.group(1) ?? '';
    }
  }

  final String? selectedMode;
  final ValueChanged<String> onModeChanged;
  final String? suggestedMode;
  final TextEditingController? weightController;
  final TextEditingController? weightPerTinController;
  final String? weightError;
  final String? tinError;
  final String? itemNameForAutofill;

  /// When true, show all unit chips in one row with short labels (kg, bag, pc, …).
  final bool compactLayout;

  static const modes = [
    StockTrackingMode.looseKg,
    StockTrackingMode.wholesaleBag,
    StockTrackingMode.retailPacket,
    StockTrackingMode.box,
    StockTrackingMode.tin,
    StockTrackingMode.piece,
  ];

  /// Compact create form: kg, bag, pc, box, tin (no separate retail packet chip).
  static const compactModes = [
    StockTrackingMode.looseKg,
    StockTrackingMode.wholesaleBag,
    StockTrackingMode.piece,
    StockTrackingMode.box,
    StockTrackingMode.tin,
  ];

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Unit type *',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'How you count this item when buying and in stock.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (suggestedMode != null) ...[
          const SizedBox(height: 8),
          Material(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.lightbulb_outline, size: 20),
              title: Text(
                'Suggested: ${StockTrackingMode.shortLabelForMode(suggestedMode!)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              trailing: TextButton(
                onPressed: () {
                  onModeChanged(suggestedMode!);
                  _autofillWeightFromName(suggestedMode!);
                },
                child: const Text('Use'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (compactLayout)
          _compactModeChips(context)
        else
          _modeChips(context, modes),
        const SizedBox(height: 12),
        if (selectedMode == StockTrackingMode.wholesaleBag ||
            selectedMode == StockTrackingMode.retailPacket) ...[
          TextField(
            controller: weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: selectedMode == StockTrackingMode.wholesaleBag
                  ? 'Kg per bag *'
                  : 'Kg per packet (optional)',
              errorText: weightError,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (selectedMode == StockTrackingMode.tin) ...[
          TextField(
            controller: weightPerTinController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Litres / kg per tin (optional)',
              errorText: tinError,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (preview != null && !compactLayout) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(preview, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _compactModeChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in compactModes)
          ChoiceChip(
            label: Text(StockTrackingMode.shortLabelForMode(m)),
            selected: m == StockTrackingMode.piece
                ? StockTrackingMode.isPieceLikeMode(selectedMode)
                : selectedMode == m,
            onSelected: (_) {
              onModeChanged(m);
              _autofillWeightFromName(m);
            },
          ),
      ],
    );
  }

  Widget _modeChips(BuildContext context, List<String> modeList) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in modeList)
          ChoiceChip(
            label: Text(StockTrackingMode.shortLabelForMode(m)),
            selected: selectedMode == m,
            onSelected: (_) {
              onModeChanged(m);
              _autofillWeightFromName(m);
            },
          ),
      ],
    );
  }

  String? _buildPreview() {
    if (selectedMode == null) return null;
    final unit = StockTrackingMode.catalogUnitForMode(selectedMode!);
    const sampleQty = 100.0;
    if (selectedMode == StockTrackingMode.wholesaleBag ||
        selectedMode == StockTrackingMode.retailPacket) {
      final w = double.tryParse(weightController?.text.trim() ?? '');
      if (w == null || w <= 0) {
        return 'Enter weight to see total kg equivalent.';
      }
      final primary = stockDisplayPrimary(sampleQty, unit);
      final kg = sampleQty * w;
      return '$primary\n(${formatStockQtyNumber(kg)} kg total)';
    }
    if (selectedMode == StockTrackingMode.looseKg) {
      return '${formatStockQtyNumber(sampleQty)} kg';
    }
    return stockDisplayPrimary(sampleQty, unit);
  }
}
