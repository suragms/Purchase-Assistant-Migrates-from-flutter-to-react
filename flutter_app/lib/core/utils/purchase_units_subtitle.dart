import '../json_coerce.dart';
import '../providers/home_dashboard_provider.dart';
import '../../features/home/home_pack_unit_word.dart';
import '../../features/home/presentation/widgets/home_formatters.dart';

/// Sum bag/box/tin/kg from trade purchase line maps (list API JSON).
String purchaseUnitsSubtitleFromLines(List<dynamic> lines) {
  var bags = 0.0;
  var boxes = 0.0;
  var tins = 0.0;
  var kg = 0.0;
  for (final raw in lines) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final qty = coerceToDouble(m['qty']);
    if (qty <= 0) continue;
    final ut = (m['unit_type'] ?? m['unit'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final u = ut == 'sack' ? 'bag' : ut;
    if (u == 'bag') {
      bags += qty;
    } else if (u == 'box') {
      boxes += qty;
    } else if (u == 'tin') {
      tins += qty;
    } else if (u == 'kg' || u == 'kilogram') {
      kg += qty;
    } else {
      final tw = coerceToDoubleNullable(m['total_weight']);
      if (tw != null && tw > 0) {
        kg += tw;
      } else {
        final kpu = coerceToDoubleNullable(m['kg_per_unit'] ??
            m['weight_per_unit']);
        if (kpu != null && kpu > 0) kg += qty * kpu;
      }
    }
  }
  return purchaseUnitsSubtitleFromMap({
    'total_bags': bags,
    'total_boxes': boxes,
    'total_tins': tins,
    'total_kg': kg,
  });
}

/// Compact bags · boxes · tins · kg line for report/home breakdown rows.
String purchaseUnitsSubtitleFromMap(Map<String, dynamic> m) {
  final parts = <String>[];
  final bags = coerceToDouble(m['total_bags'] ?? m['bags']);
  final boxes = coerceToDouble(m['total_boxes'] ?? m['boxes']);
  final tins = coerceToDouble(m['total_tins'] ?? m['tins']);
  final kg = coerceToDouble(m['total_kg'] ?? m['kg']);
  if (bags > 0) {
    parts.add('${homeFmtQty(bags)} ${homePackUnitWord('BAG', bags)}');
  }
  if (boxes > 0) {
    parts.add('${homeFmtQty(boxes)} ${homePackUnitWord('BOX', boxes)}');
  }
  if (tins > 0) {
    parts.add('${homeFmtQty(tins)} ${homePackUnitWord('TIN', tins)}');
  }
  if (kg > 0) parts.add('${homeFmtQty(kg)} KG');
  if (parts.isNotEmpty) return parts.join(' · ');
  final qty = coerceToDouble(m['total_qty'] ?? m['qty']);
  final unit = m['unit']?.toString() ?? '';
  if (qty > 0 && unit.isNotEmpty) {
    return '${homeFmtQty(qty)} ${unit.toUpperCase()}';
  }
  if (qty > 0) return homeFmtQty(qty);
  return '';
}

String categoryStatUnitsSubtitle(CategoryUnitTotals units, {double totalKg = 0}) {
  final parts = <String>[];
  if (units.bags > 0) {
    parts.add('${homeFmtQty(units.bags)} ${homePackUnitWord('BAG', units.bags)}');
  }
  if (units.boxes > 0) {
    parts.add('${homeFmtQty(units.boxes)} ${homePackUnitWord('BOX', units.boxes)}');
  }
  if (units.tins > 0) {
    parts.add('${homeFmtQty(units.tins)} ${homePackUnitWord('TIN', units.tins)}');
  }
  if (totalKg > 0) parts.add('${homeFmtQty(totalKg)} KG');
  return parts.join(' · ');
}
