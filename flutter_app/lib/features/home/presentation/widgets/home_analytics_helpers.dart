import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/purchase_units_subtitle.dart';
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

/// Period-scoped purchase unit totals from dashboard snapshot.
String purchasedUnitsLine(HomeDashboardData dash) {
  final parts = <String>[];
  if (dash.totalBags > 0) {
    parts.add(
      '${homeFmtQty(dash.totalBags)} ${homePackUnitWord('BAG', dash.totalBags)}',
    );
  }
  if (dash.totalBoxes > 0) {
    parts.add(
      '${homeFmtQty(dash.totalBoxes)} ${homePackUnitWord('BOX', dash.totalBoxes)}',
    );
  }
  if (dash.totalTins > 0) {
    parts.add(
      '${homeFmtQty(dash.totalTins)} ${homePackUnitWord('TIN', dash.totalTins)}',
    );
  }
  if (dash.totalKg > 0) parts.add('${homeFmtQty(dash.totalKg)} KG');
  if (parts.isNotEmpty) return parts.join(' · ');
  if (dash.purchaseCount > 0) return '${dash.purchaseCount} purchases';
  return 'No purchases in period';
}

bool _sliceHasActivity({required double amount, required double qty}) =>
    amount > 0 || qty > 0;

List<HomeAnalyticsSlice> _slicesFromItemMaps(
  List<Map<String, dynamic>> rows,
  List<Color> palette,
) {
  final out = <HomeAnalyticsSlice>[];
  for (var i = 0; i < rows.length && i < 8; i++) {
    final r = rows[i];
    final amount = coerceToDouble(
      r['total_purchase'] ?? r['total_amount'] ?? r['amount'],
    );
    final qty = coerceToDouble(r['total_qty'] ?? r['qty']);
    if (!_sliceHasActivity(amount: amount, qty: qty)) continue;
    final name = r['item_name']?.toString().trim() ??
        r['name']?.toString().trim() ??
        '—';
    final unit = r['unit']?.toString() ?? '';
    final sub = qty > 0 && unit.isNotEmpty
        ? '${homeFmtQty(qty)} ${unit.toUpperCase()}'
        : (qty > 0 ? homeFmtQty(qty) : unit);
    out.add(
      HomeAnalyticsSlice(
        title: name,
        subtitle: sub,
        amount: amount > 0 ? amount : qty,
        color: palette[out.length % palette.length],
      ),
    );
  }
  return out;
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

String _mapQtyLine(Map<String, dynamic> m) => purchaseUnitsSubtitleFromMap(m);

List<HomeAnalyticsSlice> homeAnalyticsSlicesForTab({
  required HomeBreakdownTab tab,
  required HomeDashboardData dash,
  HomeShellReportsBundle? shell,
}) {
  final palette = HexaColors.chartPalette;
  final out = <HomeAnalyticsSlice>[];

  switch (tab) {
    case HomeBreakdownTab.category:
      final rows = dash.categories
          .where((c) => _sliceHasActivity(amount: c.totalAmount, qty: c.totalQty))
          .toList()
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
          if (!_sliceHasActivity(amount: s.totalAmount, qty: s.totalQty)) {
            continue;
          }
          out.add(
            HomeAnalyticsSlice(
              title: s.label,
              subtitle: s.totalQty > 0 ? homeFmtQty(s.totalQty) : '',
              amount: s.totalAmount > 0 ? s.totalAmount : s.totalQty,
              color: palette[out.length % palette.length],
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
          final amount = coerceToDouble(r['total_purchase'] ?? r['total_amount']);
          final qty = coerceToDouble(r['total_qty'] ?? r['qty']);
          if (!_sliceHasActivity(amount: amount, qty: qty)) continue;
          final label = r['type_name']?.toString().trim() ??
              r['label']?.toString() ??
              '—';
          out.add(
            HomeAnalyticsSlice(
              title: label,
              subtitle: _mapQtyLine(r),
              amount: amount > 0 ? amount : qty,
              color: palette[out.length % palette.length],
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
        final amount = coerceToDouble(r['total_purchase']);
        final qty = coerceToDouble(r['total_qty'] ?? r['qty']);
        if (!_sliceHasActivity(amount: amount, qty: qty)) continue;
        out.add(
          HomeAnalyticsSlice(
            title: r['supplier_name']?.toString() ?? '—',
            subtitle: _mapQtyLine(r),
            amount: amount > 0 ? amount : qty,
            color: palette[out.length % palette.length],
          ),
        );
      }
    case HomeBreakdownTab.items:
      final itemRows = List<ItemSliceStat>.from(dash.itemSlices)
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      for (var i = 0; i < itemRows.length && out.length < 8; i++) {
        final it = itemRows[i];
        if (!_sliceHasActivity(amount: it.totalAmount, qty: it.totalQty)) {
          continue;
        }
        final sub = it.totalQty > 0
            ? '${homeFmtQty(it.totalQty)} ${it.unit.trim().toUpperCase()}'
            : it.unit;
        out.add(
          HomeAnalyticsSlice(
            title: it.name,
            subtitle: sub,
            amount: it.totalAmount > 0 ? it.totalAmount : it.totalQty,
            color: palette[out.length % palette.length],
          ),
        );
      }
      if (out.isEmpty && shell != null && shell.items.isNotEmpty) {
        final shellRows = List<Map<String, dynamic>>.from(shell.items)
          ..sort(
            (a, b) => coerceToDouble(b['total_purchase'])
                .compareTo(coerceToDouble(a['total_purchase'])),
          );
        out.addAll(_slicesFromItemMaps(shellRows, palette));
      }
      if (out.isEmpty && dash.purchaseCount > 0) {
        for (final c in dash.categories) {
          for (final it in c.items) {
            if (out.length >= 8) break;
            if (!_sliceHasActivity(amount: it.amount, qty: it.qty)) continue;
            final sub = it.qty > 0
                ? '${homeFmtQty(it.qty)} ${it.unit.trim().toUpperCase()}'
                : it.unit;
            out.add(
              HomeAnalyticsSlice(
                title: it.name,
                subtitle: sub,
                amount: it.amount,
                color: palette[out.length % palette.length],
              ),
            );
          }
          if (out.length >= 8) break;
        }
      }
  }
  return out;
}

String homeAnalyticsEmptyHint(HomeBreakdownTab tab, HomeDashboardData dash) {
  if (dash.purchaseCount > 0) {
    return switch (tab) {
      HomeBreakdownTab.category => 'No category breakdown for this period',
      HomeBreakdownTab.subcategory => 'No subcategory breakdown for this period',
      HomeBreakdownTab.supplier => 'No supplier breakdown for this period',
      HomeBreakdownTab.items => 'No item breakdown for this period',
    };
  }
  return 'No item movement in this view';
}

String homeBreakdownTabQuery(HomeBreakdownTab tab) {
  return switch (tab) {
    HomeBreakdownTab.category => 'category',
    HomeBreakdownTab.subcategory => 'subcategory',
    HomeBreakdownTab.supplier => 'supplier',
    HomeBreakdownTab.items => 'items',
  };
}
