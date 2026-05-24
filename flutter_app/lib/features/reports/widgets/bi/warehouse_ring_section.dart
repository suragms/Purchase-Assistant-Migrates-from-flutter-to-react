import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/warehouse_units_breakdown_line.dart';
import '../../../../widgets/spend_ring_chart.dart';
import 'breakdown_legend_list.dart';
import 'reports_bi_slice.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Interactive donut + legend for Reports BI tabs.
class WarehouseRingSection extends StatefulWidget {
  const WarehouseRingSection({
    super.key,
    required this.slices,
    required this.centerLabel,
    this.loading = false,
    this.onSliceTap,
    this.unitSegments = const [],
    this.expanded = false,
  });

  final List<ReportsBiSlice> slices;
  final String centerLabel;
  final bool loading;
  final void Function(int index, ReportsBiSlice slice)? onSliceTap;
  final List<WarehouseUnitSegment> unitSegments;
  final bool expanded;

  @override
  State<WarehouseRingSection> createState() => _WarehouseRingSectionState();
}

class _WarehouseRingSectionState extends State<WarehouseRingSection> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final slices = widget.slices;
    final total = slices.fold<double>(0, (s, x) => s + x.amount);
    final width = MediaQuery.sizeOf(context).width;
    final scale = widget.expanded ? 0.68 : 0.52;
    final maxD = widget.expanded ? 280.0 : 200.0;
    final minD = widget.expanded ? 160.0 : 120.0;
    final diameter = math.min(width * scale, maxD).clamp(minD, maxD);
    final values = slices.map((s) => s.amount).where((a) => a > 0).toList();
    final colors =
        slices.where((s) => s.amount > 0).map((s) => s.color).toList();
    final activeCount = slices.where((s) => s.amount > 0).length;
    final unitFont = widget.expanded ? 12.0 : 10.0;

    return Column(
      children: [
        SpendRingChart(
          diameter: diameter,
          strokeWidth: widget.expanded ? 16 : 14,
          values: values.isEmpty ? const [1] : values,
          colors: values.isEmpty ? const [Color(0xFFE2E8F0)] : colors,
          centerChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _inr0(total),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.expanded ? 17 : 14,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3B6D11),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                activeCount == 0
                    ? widget.centerLabel
                    : '$activeCount ${widget.centerLabel}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
              if (widget.unitSegments.isNotEmpty) ...[
                const SizedBox(height: 6),
                WarehouseUnitsBreakdownLine(
                  segments: widget.unitSegments,
                  fontSize: unitFont,
                  compact: !widget.expanded,
                ),
              ],
            ],
          ),
          onSectionTap: values.isEmpty
              ? null
              : (i) {
                  setState(() => _selected = i);
                  if (widget.onSliceTap != null && i < slices.length) {
                    widget.onSliceTap!(i, slices[i]);
                  }
                },
        ),
        const SizedBox(height: 10),
        BreakdownLegendList(
          slices: slices,
          selectedIndex: _selected,
          onTapIndex: widget.onSliceTap == null
              ? null
              : (i) {
                  setState(() => _selected = i);
                  if (i < slices.length) widget.onSliceTap!(i, slices[i]);
                },
        ),
      ],
    );
  }
}
