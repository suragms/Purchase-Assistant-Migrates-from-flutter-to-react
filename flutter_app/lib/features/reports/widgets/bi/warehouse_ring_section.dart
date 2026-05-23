import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  });

  final List<ReportsBiSlice> slices;
  final String centerLabel;
  final bool loading;
  final void Function(int index, ReportsBiSlice slice)? onSliceTap;

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
    final diameter = math.min(width * 0.52, 200.0).clamp(120.0, 200.0);
    final values = slices.map((s) => s.amount).where((a) => a > 0).toList();
    final colors = slices.where((s) => s.amount > 0).map((s) => s.color).toList();

    return Column(
      children: [
        SpendRingChart(
          diameter: diameter,
          strokeWidth: 14,
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF3B6D11),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${slices.where((s) => s.amount > 0).length} ${widget.centerLabel}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
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
