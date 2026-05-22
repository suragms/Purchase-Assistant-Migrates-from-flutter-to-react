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

  static Box get _purchaseWizardDraft => Hive.box(_boxPurchaseWizardDraft);

  /// JSON blob for incomplete purchase wizard (same shape as prefs draft).
  static Future<void> putPurchaseWizardDraft(String businessId, String json) async {
    await _purchaseWizardDraft.put(businessId, json);
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
    final v = _purchaseWizardDraft.get(businessId);
    if (v is! String || v.isEmpty) return null;
    if (purchaseWizardDraftJsonIsExpired(v)) {
      unawaited(clearPurchaseWizardDraft(businessId));
      return null;
    }
    return v;
  }

  static Future<void> clearPurchaseWizardDraft(String businessId) async {
    await _purchaseWizardDraft.delete(businessId);
  }

  static Box get _cache => Hive.box(_boxCache);
  static Box get _entries => Hive.box(_boxEntries);
  static Box get _scanQueue => Hive.box(_boxScanQueue);

  /// Queue a scan image locally for offline tolerance.
  /// Stores bytes as base64 string to keep Hive portable.
  static Future<String> queueScanJob({
    required String businessId,
    required List<int> jpegBytes,
  }) async {
    final id = 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final b64 = base64Encode(jpegBytes);
    await _scanQueue.put(id, {
      'id': id,
      'businessId': businessId,
      'jpegB64': b64,
      'status': 'pending', // pending|uploaded|done|failed
      'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  static List<Map<String, dynamic>> getPendingScanJobs(String businessId) {
    final out = <Map<String, dynamic>>[];
    for (final k in _scanQueue.keys) {
      final v = _scanQueue.get(k);
      if (v is Map &&
          v['businessId']?.toString() == businessId &&
          v['status']?.toString() == 'pending') {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  static Future<void> markScanJobStatus(String id, String status) async {
    final v = _scanQueue.get(id);
    if (v is! Map) return;
    final m = Map<String, dynamic>.from(v);
    m['status'] = status;
    m['updatedAt'] = DateTime.now().toIso8601String();
    await _scanQueue.put(id, m);
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
    await _cache.put('dashboard', {
      ...summary,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Returns cached analytics summary map (no `cachedAt` strip) or null if stale/missing.
  static Map<String, dynamic>? getCachedDashboardSummary() {
    final raw = _cache.get('dashboard');
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
    final kind = entryData['kind']?.toString() ?? 'unknown';
    final businessId = entryData['businessId']?.toString() ?? '';
    final fingerprint = entryData['fingerprint']?.toString() ?? '';
    // Prevent accidental duplicate queueing (double-tap / retry spam).
    if (fingerprint.isNotEmpty) {
      for (final k in _entries.keys) {
        final v = _entries.get(k);
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
    await _entries.put(id, {
      'id': id,
      'data': entryData,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> getPendingEntries() {
    final out = <Map<String, dynamic>>[];
    for (final k in _entries.keys) {
      final v = _entries.get(k);
      if (v is Map && v['status'] == 'pending') {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  /// Pending warehouse stock verify / audit line actions for [businessId].
  static int pendingStockQueueCount(String businessId) {
    var n = 0;
    for (final e in getPendingEntries()) {
      final data = e['data'];
      if (data is! Map) continue;
      if (data['businessId']?.toString() != businessId) continue;
      final kind = data['kind']?.toString() ?? '';
      if (kind == 'stock_verify' || kind == 'stock_audit_line') n++;
    }
    return n;
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
    await _entries.delete(id);
  }

  static Future<void> cacheSuppliers(List<dynamic> list) async {
    await _cache.put('suppliers', list);
  }

  static List<dynamic>? getCachedSuppliers() =>
      _cache.get('suppliers') as List<dynamic>?;

  static Future<void> cacheCatalogItems(List<dynamic> list) async {
    await _cache.put('catalog_items', list);
  }

  static List<dynamic>? getCachedCatalogItems() =>
      _cache.get('catalog_items') as List<dynamic>?;

  static String _tradeDashKey(String businessId, String from, String to) =>
      'trade_dash|$businessId|$from|$to';

  static Future<void> cacheTradeDashboardSnapshot(
    String businessId,
    String from,
    String to,
    Map<String, dynamic> snap,
  ) async {
    await _cache.put(_tradeDashKey(businessId, from, to), {
      ...snap,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  static Map<String, dynamic>? getCachedTradeDashboardSnapshot(
    String businessId,
    String from,
    String to,
  ) {
    final raw = _cache.get(_tradeDashKey(businessId, from, to));
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
    await _cache.put(_homeShellKey(businessId, from, to), {
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
    final raw = _cache.get(_homeShellKey(businessId, from, to));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Drops Hive-backed trade/home/report aggregates for [businessId], plus the legacy
  /// `dashboard` summary blob, after mutations so offline seeds cannot show pre-delete totals.
  static Future<void> bustTradeAggregateCachesForBusiness(String businessId) async {
    final pDash = 'trade_dash|$businessId|';
    final pShell = 'home_shell|$businessId|';
    final pTp = 'reports_tp|$businessId|';
    for (final k in _cache.keys.toList()) {
      final ks = k.toString();
      if (ks.startsWith(pDash) || ks.startsWith(pShell) || ks.startsWith(pTp)) {
        await _cache.delete(k);
      }
    }
    await _cache.delete('dashboard');
  }

  static String _cloudCostKey(String businessId) => 'cloud_cost|$businessId';

  static Future<void> cacheCloudCost(
    String businessId,
    Map<String, dynamic> m,
  ) async {
    await _cache.put(_cloudCostKey(businessId), {
      ...m,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  static Map<String, dynamic>? getCachedCloudCost(String businessId) {
    final raw = _cache.get(_cloudCostKey(businessId));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  static String _reportsTpKey(String businessId, String from, String to) =>
      'reports_tp|$businessId|$from|$to';

  /// Raw JSON array string of `/trade-purchases` list for SSOT Reports.
  static Future<void> cacheReportsTradePurchasesJson(
      String businessId,
      String from,
      String to,
      String jsonList) async {
    await _cache.put(_reportsTpKey(businessId, from, to), jsonList);
  }

  static String? getReportsTradePurchasesJson(
      String businessId,
      String from,
      String to,
      ) {
    final v = _cache.get(_reportsTpKey(businessId, from, to));
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  static String _assistantChatKey(String businessId) => 'assistant_chat_v1|$businessId';

  /// Last assistant thread turns (plain text only) for restore after navigation.
  static Future<void> putAssistantChatMessages(
    String businessId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _cache.put(_assistantChatKey(businessId), jsonEncode(rows));
  }

  static List<Map<String, dynamic>>? getAssistantChatMessages(String businessId) {
    final s = _cache.get(_assistantChatKey(businessId));
    if (s is! String || s.isEmpty) return null;
    try {
      final d = jsonDecode(s);
      if (d is! List) return null;
      return [
        for (final e in d)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAssistantChatMessages(String businessId) async {
    await _cache.delete(_assistantChatKey(businessId));
  }
}
