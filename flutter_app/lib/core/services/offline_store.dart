import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Local persistence for offline-first UX (dashboard cache, future entry queue).
class OfflineStore {
  OfflineStore._();

  static const _boxCache = 'offline_cache';
  static const _boxEntries = 'offline_entries';
  static const _boxPurchaseWizardDraft = 'purchase_wizard_draft';
  static const _boxScanQueue = 'scan_queue';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxCache);
    await Hive.openBox(_boxEntries);
    await Hive.openBox(_boxPurchaseWizardDraft);
    await Hive.openBox(_boxScanQueue);
  }

  /// Hive may not be ready yet on cold web load — never crash UI reads.
  static Box? _openBox(String name) {
    try {
      if (Hive.isBoxOpen(name)) return Hive.box(name);
    } catch (_) {}
    return null;
  }

  static Box? get _purchaseWizardDraft => _openBox(_boxPurchaseWizardDraft);

  /// JSON blob for incomplete purchase wizard (same shape as prefs draft).
  static Future<void> putPurchaseWizardDraft(String businessId, String json) async {
    final box = _purchaseWizardDraft;
    if (box == null) return;
    await box.put(businessId, json);
  }

  /// True when [json] has `draftWizardMeta.savedAt` older than 24 hours.
  /// Malformed JSON is treated as expired.
  static bool purchaseWizardDraftJsonIsExpired(String json) {
    try {
      final o = jsonDecode(json);
      if (o is! Map) return true;
      final meta = o['draftWizardMeta'];
      if (meta is! Map) return false;
      final at = DateTime.tryParse(meta['savedAt']?.toString() ?? '');
      if (at == null) return false;
      return DateTime.now().difference(at) > const Duration(hours: 24);
    } catch (_) {
      return true;
    }
  }

  static String? getPurchaseWizardDraft(String businessId) {
    final box = _purchaseWizardDraft;
    if (box == null) return null;
    final v = box.get(businessId);
    if (v is! String || v.isEmpty) return null;
    if (purchaseWizardDraftJsonIsExpired(v)) {
      unawaited(clearPurchaseWizardDraft(businessId));
      return null;
    }
    return v;
  }

  static Future<void> clearPurchaseWizardDraft(String businessId) async {
    final box = _purchaseWizardDraft;
    if (box == null) return;
    await box.delete(businessId);
  }

  static Box? get _cache => _openBox(_boxCache);
  static Box? get _entries => _openBox(_boxEntries);
  static Box? get _scanQueue => _openBox(_boxScanQueue);

  /// Queue a scan image locally for offline tolerance.
  /// Stores bytes as base64 string to keep Hive portable.
  static Future<String> queueScanJob({
    required String businessId,
    required List<int> jpegBytes,
  }) async {
    final id = 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final box = _scanQueue;
    if (box == null) return id;
    final b64 = base64Encode(jpegBytes);
    await box.put(id, {
      'id': id,
      'businessId': businessId,
      'jpegB64': b64,
      'status': 'pending', // pending|uploaded|done|failed
      'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  static List<Map<String, dynamic>> getPendingScanJobs(String businessId) {
    final box = _scanQueue;
    if (box == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final k in box.keys) {
      final v = box.get(k);
      if (v is Map &&
          v['businessId']?.toString() == businessId &&
          v['status']?.toString() == 'pending') {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  static Future<void> markScanJobStatus(String id, String status) async {
    final box = _scanQueue;
    if (box == null) return;
    final v = box.get(id);
    if (v is! Map) return;
    final m = Map<String, dynamic>.from(v);
    m['status'] = status;
    m['updatedAt'] = DateTime.now().toIso8601String();
    await box.put(id, m);
  }

  static List<int>? scanJobBytes(Map<String, dynamic> job) {
    final b64 = job['jpegB64']?.toString();
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheDashboardMap(Map<String, dynamic> summary) async {
    final box = _cache;
    if (box == null) return;
    await box.put('dashboard', {
      ...summary,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Returns cached analytics summary map (no `cachedAt` strip) or null if stale/missing.
  static Map<String, dynamic>? getCachedDashboardSummary() {
    final box = _cache;
    if (box == null) return null;
    final raw = box.get('dashboard');
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final at = m['cachedAt'] as String?;
    if (at == null) return null;
    final cachedAt = DateTime.tryParse(at);
    if (cachedAt == null) return null;
    if (DateTime.now().difference(cachedAt) > const Duration(hours: 2)) {
      return null;
    }
    return m;
  }

  static Future<void> queueEntry(Map<String, dynamic> entryData) async {
    final entries = _entries;
    if (entries == null) return;
    final kind = entryData['kind']?.toString() ?? 'unknown';
    final businessId = entryData['businessId']?.toString() ?? '';
    final fingerprint = entryData['fingerprint']?.toString() ?? '';
    // Prevent accidental duplicate queueing (double-tap / retry spam).
    if (fingerprint.isNotEmpty) {
      for (final k in entries.keys) {
        final v = entries.get(k);
        if (v is Map && v['status'] == 'pending') {
          final data = v['data'];
          if (data is Map &&
              data['fingerprint']?.toString() == fingerprint &&
              data['businessId']?.toString() == businessId &&
              data['kind']?.toString() == kind) {
            return;
          }
        }
      }
    }
    final id = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    await entries.put(id, {
      'id': id,
      'data': entryData,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> getPendingEntries() {
    final entries = _entries;
    if (entries == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final k in entries.keys) {
      final v = entries.get(k);
      if (v is Map && v['status'] == 'pending') {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  /// Pending warehouse stock verify / audit / delivery actions for [businessId].
  static int pendingStockQueueCount(String businessId) {
    var n = 0;
    for (final e in getPendingEntries()) {
      final data = e['data'];
      if (data is! Map) continue;
      if (data['businessId']?.toString() != businessId) continue;
      final kind = data['kind']?.toString() ?? '';
      if (kind == 'stock_verify' ||
          kind == 'stock_audit_line' ||
          kind == 'purchase_arrive') {
        n++;
      }
    }
    return n;
  }

  static Future<void> queuePurchaseArrive({
    required String businessId,
    required String purchaseId,
    String? notes,
  }) async {
    await queueEntry({
      'kind': 'purchase_arrive',
      'businessId': businessId,
      'fingerprint': 'arrive|$purchaseId',
      'purchase_id': purchaseId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  static Future<void> queueStockVerify({
    required String businessId,
    required String itemId,
    required num countedQty,
    required String reason,
    String adjustmentType = 'verification',
    String? notes,
  }) async {
    await queueEntry({
      'kind': 'stock_verify',
      'businessId': businessId,
      'fingerprint': 'verify|$itemId|$countedQty',
      'item_id': itemId,
      'counted_qty': countedQty,
      'reason': reason,
      'adjustment_type': adjustmentType,
      if (notes != null) 'notes': notes,
    });
  }

  static Future<void> markSynced(String id) async {
    final entries = _entries;
    if (entries == null) return;
    await entries.delete(id);
  }

  static Future<void> cacheSuppliers(List<dynamic> list) async {
    final box = _cache;
    if (box == null) return;
    await box.put('suppliers', list);
  }

  static List<dynamic>? getCachedSuppliers() {
    final box = _cache;
    if (box == null) return null;
    return box.get('suppliers') as List<dynamic>?;
  }

  static Future<void> cacheCatalogItems(List<dynamic> list) async {
    final box = _cache;
    if (box == null) return;
    await box.put('catalog_items', list);
  }

  static List<dynamic>? getCachedCatalogItems() {
    final box = _cache;
    if (box == null) return null;
    return box.get('catalog_items') as List<dynamic>?;
  }

  static String _tradeDashKey(String businessId, String from, String to) =>
      'trade_dash|$businessId|$from|$to';

  static Future<void> cacheTradeDashboardSnapshot(
    String businessId,
    String from,
    String to,
    Map<String, dynamic> snap,
  ) async {
    final box = _cache;
    if (box == null) return;
    await box.put(_tradeDashKey(businessId, from, to), {
      ...snap,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  static Map<String, dynamic>? getCachedTradeDashboardSnapshot(
    String businessId,
    String from,
    String to,
  ) {
    final box = _cache;
    if (box == null) return null;
    final raw = box.get(_tradeDashKey(businessId, from, to));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  static String _homeShellKey(String businessId, String from, String to) =>
      'home_shell|$businessId|$from|$to';

  static Future<void> cacheHomeShellReports(
    String businessId,
    String from,
    String to, {
    required List<Map<String, dynamic>> subcategories,
    required List<Map<String, dynamic>> suppliers,
    required List<Map<String, dynamic>> items,
  }) async {
    final box = _cache;
    if (box == null) return;
    await box.put(_homeShellKey(businessId, from, to), {
      'subcategories': subcategories,
      'suppliers': suppliers,
      'items': items,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  static Map<String, dynamic>? getCachedHomeShellReports(
    String businessId,
    String from,
    String to,
  ) {
    final box = _cache;
    if (box == null) return null;
    final raw = box.get(_homeShellKey(businessId, from, to));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Drops Hive-backed trade/home/report aggregates for [businessId], plus the legacy
  /// `dashboard` summary blob, after mutations so offline seeds cannot show pre-delete totals.
  static Future<void> bustTradeAggregateCachesForBusiness(String businessId) async {
    final box = _cache;
    if (box == null) return;
    final pDash = 'trade_dash|$businessId|';
    final pShell = 'home_shell|$businessId|';
    final pTp = 'reports_tp|$businessId|';
    for (final k in box.keys.toList()) {
      final ks = k.toString();
      if (ks.startsWith(pDash) || ks.startsWith(pShell) || ks.startsWith(pTp)) {
        await box.delete(k);
      }
    }
    await box.delete('dashboard');
  }

  static String _reportsTpKey(String businessId, String from, String to) =>
      'reports_tp|$businessId|$from|$to';

  /// Raw JSON array string of `/trade-purchases` list for SSOT Reports.
  static Future<void> cacheReportsTradePurchasesJson(
      String businessId,
      String from,
      String to,
      String jsonList) async {
    final box = _cache;
    if (box == null) return;
    await box.put(_reportsTpKey(businessId, from, to), jsonList);
  }

  static String? getReportsTradePurchasesJson(
      String businessId,
      String from,
      String to,
      ) {
    final box = _cache;
    if (box == null) return null;
    final v = box.get(_reportsTpKey(businessId, from, to));
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

}
