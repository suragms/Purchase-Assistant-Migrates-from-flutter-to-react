import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../home_pack_unit_word.dart';
import 'home_formatters.dart';

/// One ranked row + ring slice for the analytics card.
class HomeAnalyticsSlice {
  const HomeAnalyticsSlice({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final double amount;
  final Color color;
  final VoidCallback? onTap;
}

String inventoryUnitsLine(HomeInventorySummary inv) {
  final parts = <String>[];
  if (inv.bags > 0) {
    parts.add(
      '${homeFmtQty(inv.bags)} ${homePackUnitWord('BAG', inv.bags)}',
    );
  }
  if (inv.boxes > 0) {
    parts.add(
      '${homeFmtQty(inv.boxes)} ${homePackUnitWord('BOX', inv.boxes)}',
    );
  }
  if (inv.tins > 0) {
    parts.add(
      '${homeFmtQty(inv.tins)} ${homePackUnitWord('TIN', inv.tins)}',
    );
  }
  if (inv.kg > 0) parts.add('${homeFmtQty(inv.kg)} KG');
  return parts.isEmpty ? 'No stock on hand' : parts.join(' · ');
}

String _categoryQtyLine(CategoryStat c) {
  final parts = <String>[];
  if (c.units.bags > 0) {
    parts.add(
      '${homeFmtQty(c.units.bags)} ${homePackUnitWord('BAG', c.units.bags)}',
    );
  }
  if (c.units.boxes > 0) {
    parts.add(
      '${homeFmtQty(c.units.boxes)} ${homePackUnitWord('BOX', c.units.boxes)}',
    );
  }
  if (c.units.tins > 0) {
    parts.add(
      '${homeFmtQty(c.units.tins)} ${homePackUnitWord('TIN', c.units.tins)}',
    );
  }
  if (c.totalQty > 0 && parts.isEmpty) {
    parts.add(homeFmtQty(c.totalQty));
  }
  return parts.join(' · ');
}

String _mapQtyLine(Map<String, dynamic> m) {
  final qty = coerceToDouble(m['total_qty'] ?? m['qty']);
  final unit = m['unit']?.toString() ?? '';
  if (qty > 0 && unit.isNotEmpty) {
    return '${homeFmtQty(qty)} ${unit.toUpperCase()}';
  }
  if (qty > 0) return homeFmtQty(qty);
  return '';
}

List<HomeAnalyticsSlice> homeAnalyticsSlicesForTab({
  required HomeBreakdownTab tab,
  required HomeDashboardData dash,
  HomeShellReportsBundle? shell,
}) {
  final palette = HexaColors.chartPalette;
  final out = <HomeAnalyticsSlice>[];

  switch (tab) {
    case HomeBreakdownTab.category:
      final rows = dash.categories.where((c) => c.totalAmount > 0).toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      for (var i = 0; i < rows.length && i < 8; i++) {
        final c = rows[i];
        out.add(
          HomeAnalyticsSlice(
            title: c.categoryName,
            subtitle: _categoryQtyLine(c),
            amount: c.totalAmount,
            color: palette[i % palette.length],
          ),
        );
      }
    case HomeBreakdownTab.subcategory:
      if (dash.subcategories.isNotEmpty) {
        final rows = List<SubcategoryStat>.from(dash.subcategories)
          ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        for (var i = 0; i < rows.length && i < 8; i++) {
          final s = rows[i];
          out.add(
            HomeAnalyticsSlice(
              title: s.label,
              subtitle: homeFmtQty(s.totalQty),
              amount: s.totalAmount,
              color: palette[i % palette.length],
            ),
          );
        }
      } else if (shell != null) {
        final rows = List<Map<String, dynamic>>.from(shell.subcategories)
          ..sort(
            (a, b) => coerceToDouble(b['total_purchase'])
                .compareTo(coerceToDouble(a['total_purchase'])),
          );
        for (var i = 0; i < rows.length && i < 8; i++) {
          final r = rows[i];
          final label = r['type_name']?.toString().trim() ??
              r['label']?.toString() ??
              '—';
          out.add(
            HomeAnalyticsSlice(
              title: label,
              subtitle: _mapQtyLine(r),
              amount: coerceToDouble(r['total_purchase'] ?? r['total_amount']),
              color: palette[i % palette.length],
            ),
          );
        }
      }
    case HomeBreakdownTab.supplier:
      final suppliers = shell?.suppliers ?? [];
      final rows = List<Map<String, dynamic>>.from(suppliers)
        ..sort(
          (a, b) => coerceToDouble(b['total_purchase'])
              .compareTo(coerceToDouble(a['total_purchase'])),
        );
      for (var i = 0; i < rows.length && i < 8; i++) {
        final r = rows[i];
        out.add(
          HomeAnalyticsSlice(
            title: r['supplier_name']?.toString() ?? '—',
            subtitle: _mapQtyLine(r),
            amount: coerceToDouble(r['total_purchase']),
            color: palette[i % palette.length],
          ),
        );
      }
    case HomeBreakdownTab.items:
      final rows = List<ItemSliceStat>.from(dash.itemSlices)
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      for (var i = 0; i < rows.length && i < 8; i++) {
        final it = rows[i];
        final sub = it.totalQty > 0
            ? '${homeFmtQty(it.totalQty)} ${it.unit.trim().toUpperCase()}'
            : it.unit;
        out.add(
          HomeAnalyticsSlice(
            title: it.name,
            subtitle: sub,
            amount: it.totalAmount,
            color: palette[i % palette.length],
          ),
        );
      }
  }
  return out;
}

String homeBreakdownTabQuery(HomeBreakdownTab tab) {
  return switch (tab) {
    HomeBreakdownTab.category => 'category',
    HomeBreakdownTab.subcategory => 'subcategory',
    HomeBreakdownTab.supplier => 'supplier',
    HomeBreakdownTab.items => 'items',
  };
}
