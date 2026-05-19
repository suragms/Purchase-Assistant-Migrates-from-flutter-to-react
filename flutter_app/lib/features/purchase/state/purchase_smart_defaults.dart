import 'package:shared_preferences/shared_preferences.dart';

/// Local smart defaults for purchase entry (no financial truth — prefs only).
class PurchaseSmartDefaults {
  PurchaseSmartDefaults._();

  static const _kLastSupplierId = 'purchase_last_supplier_id';
  static const _kLastSupplierCatPrefix = 'purchase_last_supplier_cat_';
  static const _kLastRatePrefix = 'purchase_last_rate_';
  static const _kQtyHistPrefix = 'purchase_qty_hist_';

  static Future<void> saveLastSupplierId(String supplierId) async {
    final id = supplierId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSupplierId, id);
  }

  static Future<String?> loadLastSupplierId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kLastSupplierId)?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static Future<void> saveLastSupplierForCategory({
    required String categoryId,
    required String supplierId,
  }) async {
    final cat = categoryId.trim();
    final sup = supplierId.trim();
    if (cat.isEmpty || sup.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kLastSupplierCatPrefix$cat', sup);
  }

  static Future<String?> loadLastSupplierForCategory(String categoryId) async {
    final cat = categoryId.trim();
    if (cat.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('$_kLastSupplierCatPrefix$cat')?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static Future<void> saveLastRateForItem(String itemId, double rate) async {
    final id = itemId.trim();
    if (id.isEmpty || rate <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_kLastRatePrefix$id', rate);
  }

  static Future<double?> loadLastRateForItem(String itemId) async {
    final id = itemId.trim();
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_kLastRatePrefix$id');
  }

  static Future<void> recordQtyForItem(String itemId, double qty) async {
    final id = itemId.trim();
    if (id.isEmpty || qty <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kQtyHistPrefix$id';
    final existing = prefs.getStringList(key) ?? [];
    final next = [...existing, qty.toStringAsFixed(4)];
    while (next.length > 8) {
      next.removeAt(0);
    }
    await prefs.setStringList(key, next);
  }

  static Future<List<double>> loadQtyHistoryForItem(String itemId) async {
    final id = itemId.trim();
    if (id.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('$_kQtyHistPrefix$id') ?? [];
    final out = <double>[];
    for (final s in raw) {
      final v = double.tryParse(s);
      if (v != null && v > 0) out.add(v);
    }
    return out;
  }

  /// Suggested quantity from prior entries on this device.
  static int suggestQty(List<double> history) {
    if (history.isEmpty) return 1;
    final sum = history.reduce((a, b) => a + b);
    return (sum / history.length).round().clamp(1, 999999);
  }
}
