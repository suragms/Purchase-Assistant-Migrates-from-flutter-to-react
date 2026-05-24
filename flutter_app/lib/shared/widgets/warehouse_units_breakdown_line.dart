import 'package:flutter/material.dart';

import '../../core/providers/home_dashboard_provider.dart';
import '../../core/reporting/trade_report_aggregate.dart';
import '../../features/home/home_pack_unit_word.dart';
import '../../features/home/presentation/widgets/home_formatters.dart';

String _fmtTradeQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

List<WarehouseUnitSegment> warehouseUnitSegmentsFromTradeTotals(
  TradeReportTotals totals,
) {
  final out = <WarehouseUnitSegment>[];
  if (totals.bags > 0) {
    out.add(WarehouseUnitSegment(
      _fmtTradeQty(totals.bags),
      homePackUnitWord('BAG', totals.bags),
    ));
  }
  if (totals.boxes > 0) {
    out.add(WarehouseUnitSegment(
      _fmtTradeQty(totals.boxes),
      homePackUnitWord('BOX', totals.boxes),
    ));
  }
  if (totals.tins > 0) {
    out.add(WarehouseUnitSegment(
      _fmtTradeQty(totals.tins),
      homePackUnitWord('TIN', totals.tins),
    ));
  }
  if (totals.kg > 0) {
    out.add(WarehouseUnitSegment(_fmtTradeQty(totals.kg), 'KG'));
  }
  return out;
}

/// Accent color per warehouse pack unit (readable at small sizes).
Color warehouseUnitAccentColor(String unitWord) {
  final u = unitWord.toUpperCase();
  if (u.startsWith('BAG')) return const Color(0xFFDC2626);
  if (u.startsWith('BOX')) return const Color(0xFF2563EB);
  if (u.startsWith('TIN')) return const Color(0xFF7C3AED);
  if (u == 'KG' || u.endsWith('KG')) return const Color(0xFFEA580C);
  if (u.startsWith('PCS') || u == 'PC') return const Color(0xFF0D9488);
  return const Color(0xFF475569);
}

class WarehouseUnitSegment {
  const WarehouseUnitSegment(this.qtyText, this.unitWord);

  final String qtyText;
  final String unitWord;
}

List<WarehouseUnitSegment> warehouseUnitSegmentsFromDashboard(
  HomeDashboardData data,
) {
  final out = <WarehouseUnitSegment>[];
  if (data.totalBags > 0) {
    out.add(WarehouseUnitSegment(
      homeFmtQty(data.totalBags),
      homePackUnitWord('BAG', data.totalBags),
    ));
  }
  if (data.totalBoxes > 0) {
    out.add(WarehouseUnitSegment(
      homeFmtQty(data.totalBoxes),
      homePackUnitWord('BOX', data.totalBoxes),
    ));
  }
  if (data.totalTins > 0) {
    out.add(WarehouseUnitSegment(
      homeFmtQty(data.totalTins),
      homePackUnitWord('TIN', data.totalTins),
    ));
  }
  if (data.totalKg > 0) {
    out.add(WarehouseUnitSegment(homeFmtQty(data.totalKg), 'KG'));
  }
  return out;
}

List<WarehouseUnitSegment>? warehouseUnitSegmentsFromSubtitle(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final re = RegExp(r'([\d,\.]+)\s+([A-Za-z]+)');
  final out = <WarehouseUnitSegment>[];
  for (final m in re.allMatches(trimmed)) {
    final qty = m.group(1);
    final unit = m.group(2);
    if (qty == null || unit == null) continue;
    out.add(WarehouseUnitSegment(qty, unit.toUpperCase()));
  }
  return out.isEmpty ? null : out;
}

/// Bold qty + colored unit chips (BAG / BOX / TIN / KG).
class WarehouseUnitsBreakdownLine extends StatelessWidget {
  const WarehouseUnitsBreakdownLine({
    super.key,
    required this.segments,
    this.fontSize = 12,
    this.compact = false,
    this.maxLines = 2,
  });

  final List<WarehouseUnitSegment> segments;
  final double fontSize;
  final bool compact;
  final int maxLines;

  factory WarehouseUnitsBreakdownLine.fromDashboard(
    HomeDashboardData data, {
    double fontSize = 12,
    bool compact = false,
    int maxLines = 2,
  }) {
    return WarehouseUnitsBreakdownLine(
      segments: warehouseUnitSegmentsFromDashboard(data),
      fontSize: fontSize,
      compact: compact,
      maxLines: maxLines,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final qtySize = fontSize;
    final unitSize = compact ? fontSize * 0.92 : fontSize * 0.95;
    final sep = Text(
      ' · ',
      style: TextStyle(
        fontSize: unitSize,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF94A3B8),
      ),
    );

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) children.add(sep);
      final s = segments[i];
      final color = warehouseUnitAccentColor(s.unitWord);
      children.add(
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: s.qtyText,
                style: TextStyle(
                  fontSize: qtySize,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.15,
                ),
              ),
              TextSpan(
                text: ' ${s.unitWord}',
                style: TextStyle(
                  fontSize: unitSize,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.3,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: compact ? 2 : 4,
      children: children,
    );
  }
}

/// Parses a subtitle like `613 BAGS · 400 BOXES` when possible; else plain text.
class WarehouseUnitsSubtitleText extends StatelessWidget {
  const WarehouseUnitsSubtitleText({
    super.key,
    required this.subtitle,
    this.fontSize = 11,
    this.fallbackStyle,
  });

  final String subtitle;
  final double fontSize;
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final parsed = warehouseUnitSegmentsFromSubtitle(subtitle);
    if (parsed != null && parsed.isNotEmpty) {
      return WarehouseUnitsBreakdownLine(
        segments: parsed,
        fontSize: fontSize,
        compact: true,
        maxLines: 1,
      );
    }
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: fallbackStyle ??
          TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF64748B),
          ),
    );
  }
}
