import '../json_coerce.dart';
import '../providers/home_dashboard_provider.dart';
import '../../features/home/home_pack_unit_word.dart';
import '../../features/home/presentation/widgets/home_formatters.dart';

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
