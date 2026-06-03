import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/router/navigation_ext.dart';
import '../../../core/api/fastapi_error.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/json_coerce.dart' show coerceToDoubleNullable;
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/widgets/form_field_scroll.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/snack.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show
        catalogItemIdsFromTradeJson,
        invalidateAfterDeliveryCommit,
        invalidatePurchaseWorkspace,
        invalidateWorkspaceSeedData,
        syncPurchaseStockFromPurchaseJson;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/purchase_whatsapp_prefs.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/services/purchase_accounts_share.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/services/offline_sync_service.dart';
import '../../../core/services/staff_activity_logger.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../purchase/domain/purchase_draft.dart';
import '../../purchase/mapping/ai_scan_purchase_draft_map.dart';
import '../../purchase/state/purchase_draft_provider.dart';
import '../../purchase/state/purchase_smart_defaults.dart';
import '../../purchase/state/purchase_trade_preview_provider.dart';

import '../../contacts/presentation/broker_wizard_page.dart';
import '../../contacts/presentation/supplier_create_simple.dart';
import '../../../shared/widgets/inline_search_field.dart';
import 'wizard/purchase_fast_items_step.dart';
import 'wizard/purchase_party_step.dart';
import 'wizard/purchase_review_tally_step.dart';
import 'wizard/purchase_terms_only_step.dart';
import 'widgets/purchase_item_entry_sheet.dart';
import 'widgets/purchase_saved_sheet.dart';
import 'scan_purchase_draft_logic.dart';

enum _WizardExitDraftChoice { keepEditing, saveDraft, discard }

class PurchaseEntryWizardV2 extends ConsumerStatefulWidget {
  const PurchaseEntryWizardV2({
    super.key,
    this.editingId,
    this.initialCatalogItemId,
    this.initialDraft,
    this.resumeDraft = false,
    this.aiScanToken,
    this.aiScanBaseJson,
  });

  final String? editingId;
  final String? initialCatalogItemId;

  /// Seeds the wizard after OCR / external flows (skipped when editing).
  final PurchaseDraft? initialDraft;

  /// When true after [reset], restore Hive/prefs draft (explicit “resume” flow).
  final bool resumeDraft;

  /// When set with [aiScanBaseJson], save uses `/scan-purchase-v2/update` + `/confirm` instead of POST trade purchase.
  final String? aiScanToken;

  /// Original ScanResult JSON for merge-on-save (warnings, meta, token context).
  final Map<String, dynamic>? aiScanBaseJson;

  @override
  ConsumerState<PurchaseEntryWizardV2> createState() =>
      _PurchaseEntryWizardV2State();
}

class _PurchaseEntryWizardV2State extends ConsumerState<PurchaseEntryWizardV2>
    with WidgetsBindingObserver {
  bool _isBootstrapping = false;
  String? _editBootstrapError;
  bool _isSaving = false;
  bool _formDirty = false;
  String? _previewHumanId;
  String? _editHumanId;
  String? _loadedDerivedStatus;
  double? _loadedRemaining;
  String? _inlineSaveError;
  String? _supplierFieldError;
  String? _brokerFieldError;
  List<Map<String, dynamic>>? _lastGoodSuppliers;
  List<Map<String, dynamic>>? _lastGoodBrokers;
  bool _triedEmptyCatalogBootstrap = false;
  bool _catalogLinePrefillOpened = false;

  /// When catalog line defaults reduce suppliers to a single option, we auto-pick once per signature.
  String? _lastAutoSupplierFromCatalogSig;

  /// Bumped on manual supplier pick/clear/quick-create so catalog auto-pick post-frames cannot race the user.
  int _partyUserSupplierActionGeneration = 0;

  /// Last good catalog snapshot for stale-while-revalidate UX.
  List<Map<String, dynamic>>? _lastCatalogSnapshot;

  Timer? _draftDebounce;

  /// Sync snapshot for [dispose] — no [ref] after widget teardown.
  String? _cachedDraftPrefsKey;
  String? _cachedDraftBid;
  String? _cachedDraftJson;

  /// Latest [purchase_date] per supplier from recent trade list (for autocomplete sort).
  Map<String, DateTime> _supplierLastPurchaseById = {};
  Map<String, double> _supplierBalanceById = {};

  /// Ignore stale async work when the user picks another supplier before requests finish.
  int _supplierApplySeq = 0;

  /// Mini preview on items step after adding a line (replaces snackbar).
  PurchaseLineDraft? _lineJustAdded;

  /// 0 party+terms → 1 items → 2 review.
  int _wizStep = 0;

  /// One-shot: AI bill has OCR supplier text but no `supplierId` — focus opens suggestion panel.
  bool _didAutoFocusPartyFromAiScan = false;

  /// One-shot: AI bill has supplier linked, OCR broker text, but no `brokerId` — focus broker field.
  bool _didAutoFocusBrokerFromAiScan = false;

  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _partySupplierFocus = FocusNode();
  final _partyBrokerFocus = FocusNode();
  final _termsPaymentDaysFocus = FocusNode();
  final _termsCommissionFocus = FocusNode();
  final _termsHeaderDiscFocus = FocusNode();
  final _termsNarrationFocus = FocusNode();
  final _paymentDaysCtrl = TextEditingController();
  final _headerDiscCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _deliveredRateCtrl = TextEditingController();
  final _billtyRateCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _wizardBodyScrollController = ScrollController();
  final _itemsStepListScrollController = ScrollController();

  void _partyFieldFocusNotify() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _partySupplierFocus.addListener(_partyFieldFocusNotify);
    _partyBrokerFocus.addListener(_partyFieldFocusNotify);
    bindFocusNodeScrollIntoView(_partySupplierFocus);
    bindFocusNodeScrollIntoView(_partyBrokerFocus);
    bindFocusNodeScrollIntoView(_termsPaymentDaysFocus);
    bindFocusNodeScrollIntoView(_termsCommissionFocus);
    bindFocusNodeScrollIntoView(_termsHeaderDiscFocus);
    bindFocusNodeScrollIntoView(_termsNarrationFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused && _formDirty) {
      _draftDebounce?.cancel();
      _flushDraftToPrefs();
    }
  }

  Future<void> _bootstrap() async {
    final notifier = ref.read(purchaseDraftProvider.notifier);
    if (widget.editingId != null && widget.editingId!.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = true;
        _editBootstrapError = null;
      });
      Map<String, dynamic>? raw;
      try {
        raw = await notifier.loadFromEdit(widget.editingId!);
        if (raw == null && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 420));
          if (!mounted) return;
          raw = await notifier.loadFromEdit(widget.editingId!);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _editBootstrapError = friendlyApiError(e);
          _isBootstrapping = false;
        });
        return;
      }
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _editBootstrapError = 'Could not load this purchase (timeout or incomplete data). '
              'Check your connection, pull to refresh login, then tap Retry.';
          _isBootstrapping = false;
        });
        return;
      }
      _editHumanId = raw['human_id']?.toString();
      _loadedDerivedStatus = raw['derived_status']?.toString();
      _loadedRemaining = (raw['remaining'] as num?)?.toDouble();
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _isBootstrapping = false);
    } else {
      if (!mounted) return;
      notifier.reset();
      _supplierCtrl.clear();
      _brokerCtrl.clear();
      _paymentDaysCtrl.clear();
      _headerDiscCtrl.clear();
      _commissionCtrl.clear();
      _deliveredRateCtrl.clear();
      _billtyRateCtrl.clear();
      _freightCtrl.clear();
      _invoiceCtrl.clear();
      if (widget.initialDraft != null) {
        ref
            .read(purchaseDraftProvider.notifier)
            .replaceDraft(widget.initialDraft!);
      } else if (widget.resumeDraft) {
        await _maybeRestoreDraft();
      } else {
        // Fresh new purchase — never carry over party/terms from prefs/Hive.
        await _clearDraftInPrefs();
      }
      if (!mounted) return;
      _syncControllersFromDraft();
      _maybeAutoFocusPartyForAiScan();
      _maybeAutoFocusBrokerForAiScan();
      Future.microtask(() {
        if (!mounted) return;
        ref.invalidate(catalogItemsListProvider);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Removed redundant MaterialBanner prompt — user has home page banner
      });
    }
    if (!mounted) return;
    // Defer heavy I/O — first paint is sync path above only.
    unawaited(Future<void>(() async {
      if (!mounted) return;
      await _prefetchNextHumanId();
      if (!mounted) return;
      await _openCatalogLinePrefillIfNeeded();
      if (!mounted) return;
      await _ensureCatalogSeedIfEmpty();
      if (!mounted) return;
      await _prefetchSupplierLastPurchasesMap();
    }));
  }

  Future<List<String>> _recentCatalogItemIdsForSupplier(String supplierId) async {
    final session = ref.read(sessionProvider);
    if (session == null) return const [];
    try {
      final purchases = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            supplierId: supplierId,
            limit: 25,
          );
      final ids = <String>[];
      for (final p in purchases) {
        final lines = p['lines'];
        if (lines is! List) continue;
        for (final ln in lines) {
          if (ln is! Map) continue;
          final id = ln['catalog_item_id']?.toString().trim();
          if (id == null || id.isEmpty) continue;
          if (!ids.contains(id)) ids.add(id);
          if (ids.length >= 5) return ids;
        }
      }
      return ids;
    } catch (_) {
      return const [];
    }
  }

  void _maybeAutoFocusPartyForAiScan() {
    final tok = widget.aiScanToken?.trim();
    if (tok == null || tok.isEmpty) return;
    if (_didAutoFocusPartyFromAiScan) return;
    if (_wizStep != 0) return;
    final d = ref.read(purchaseDraftProvider);
    final noId = d.supplierId == null || d.supplierId!.trim().isEmpty;
    final nameFromDraft = (d.supplierName ?? '').trim().isNotEmpty;
    final nameFromCtrl = _supplierCtrl.text.trim().isNotEmpty;
    if (!noId || (!nameFromDraft && !nameFromCtrl)) return;
    _didAutoFocusPartyFromAiScan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _wizStep != 0) return;
      FocusScope.of(context).requestFocus(_partySupplierFocus);
    });
  }

  void _maybeAutoFocusBrokerForAiScan() {
    final tok = widget.aiScanToken?.trim();
    if (tok == null || tok.isEmpty) return;
    if (_didAutoFocusBrokerFromAiScan) return;
    if (_wizStep != 0) return;
    final d = ref.read(purchaseDraftProvider);
    final supplierOk =
        d.supplierId != null && d.supplierId!.trim().isNotEmpty;
    if (!supplierOk) return;
    final noBrokerId =
        d.brokerId == null || d.brokerId!.trim().isEmpty;
    if (!noBrokerId) return;
    final nameFromDraft = (d.brokerName ?? '').trim().isNotEmpty;
    final nameFromCtrl = _brokerCtrl.text.trim().isNotEmpty;
    if (!nameFromDraft && !nameFromCtrl) return;
    _didAutoFocusBrokerFromAiScan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _wizStep != 0) return;
      FocusScope.of(context).requestFocus(_partyBrokerFocus);
    });
  }

  void _syncControllersFromDraft() {
    final d = ref.read(purchaseDraftProvider);

    /// Party fields: never blank a picked row just because prefs/API omitted the
    /// display name (`supplier_name`/`broker_name`). Only overwrite when draft
    /// has a trimmed label or we are clearing commitment (no id).
    final supplierTrimmed = (d.supplierName ?? '').trim();
    final supplierCommitted =
        d.supplierId != null && d.supplierId!.trim().isNotEmpty;
    if (supplierCommitted) {
      if (supplierTrimmed.isNotEmpty &&
          _supplierCtrl.text != supplierTrimmed) {
        _supplierCtrl.text = supplierTrimmed;
      }
    } else if (supplierTrimmed.isNotEmpty) {
      // AI / OCR name without directory id — keep text so user can pick supplier.
      if (_supplierCtrl.text != supplierTrimmed) {
        _supplierCtrl.text = supplierTrimmed;
      }
    } else if (_supplierCtrl.text.isNotEmpty) {
      _supplierCtrl.clear();
    }

    final brokerTrimmed = (d.brokerName ?? '').trim();
    final brokerCommitted =
        d.brokerId != null && d.brokerId!.trim().isNotEmpty;
    if (brokerCommitted) {
      if (brokerTrimmed.isNotEmpty && _brokerCtrl.text != brokerTrimmed) {
        _brokerCtrl.text = brokerTrimmed;
      }
    } else if (brokerTrimmed.isNotEmpty) {
      if (_brokerCtrl.text != brokerTrimmed) {
        _brokerCtrl.text = brokerTrimmed;
      }
    } else if (_brokerCtrl.text.isNotEmpty) {
      _brokerCtrl.clear();
    }
    _paymentDaysCtrl.text = d.paymentDays != null ? '${d.paymentDays}' : '';
    _headerDiscCtrl.text = d.headerDiscountPercent != null
        ? d.headerDiscountPercent!.toStringAsFixed(2)
        : '';
    if (d.commissionMode == kPurchaseCommissionModePercent) {
      _commissionCtrl.text = d.commissionPercent != null
          ? d.commissionPercent!.toStringAsFixed(2)
          : '';
    } else {
      _commissionCtrl.text = d.commissionMoney != null
          ? d.commissionMoney!.toStringAsFixed(4)
          : '';
    }
    _deliveredRateCtrl.text =
        d.deliveredRate != null ? d.deliveredRate!.toStringAsFixed(2) : '';
    _billtyRateCtrl.text =
        d.billtyRate != null ? d.billtyRate!.toStringAsFixed(2) : '';
    _freightCtrl.text =
        d.freightAmount != null ? d.freightAmount!.toStringAsFixed(2) : '';
    _invoiceCtrl.text = d.invoiceNumber ?? '';
  }

  Future<void> _ensureCatalogSeedIfEmpty() async {
    if (_triedEmptyCatalogBootstrap) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      if (catalog.isNotEmpty) return;
      _triedEmptyCatalogBootstrap = true;
      await ref.read(hexaApiProvider).bootstrapWorkspace();
      if (!mounted) return;
      invalidateWorkspaceSeedData(ref);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(suppliersListProvider);
    } catch (_) {
      _triedEmptyCatalogBootstrap = true;
    }
  }

  Future<void> _openCatalogLinePrefillIfNeeded() async {
    final cid = widget.initialCatalogItemId;
    if (cid == null || cid.isEmpty) return;
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (_catalogLinePrefillOpened) return;
    final draft = ref.read(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) return;
    if (draft.lines.isNotEmpty) return;
    _catalogLinePrefillOpened = true;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      final row = _catalogRowById(catalog, cid);
      if (row == null) return;
      final label = row['name']?.toString() ?? '';
      final unit = _catalogLineUnitFromRow(row);
      var land = 0.0;
      final lp = row['default_landing_cost'];
      if (lp is num && lp > 0) land = lp.toDouble();
      final kpb = row['default_kg_per_bag'];
      final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
      final uNorm = unit.trim().toLowerCase();
      final tax = row['tax_percent'];
      final initial = <String, dynamic>{
        'catalog_item_id': cid,
        'item_name': label,
        'qty': 1.0,
        'unit': unit,
        if (tax is num && tax > 0) 'tax_percent': tax.toDouble(),
      };
      if ((uNorm == 'bag') && kpbD != null && land > 0) {
        initial['kg_per_unit'] = kpbD;
        initial['landing_cost_per_kg'] = land / kpbD;
        initial['landing_cost'] = land;
      } else {
        initial['landing_cost'] = land;
      }
      if (!mounted) return;
      await _openItemSheet(catalog, initialOverride: initial);
    } catch (_) {}
  }

  Map<String, dynamic>? _catalogRowById(
    List<Map<String, dynamic>> catalog,
    String id,
  ) {
    for (final m in catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  /// Catalog unit for new purchase lines (bag / kg / piece / box).
  static String _catalogLineUnitFromRow(Map<String, dynamic> row) {
    for (final key in [
      'unit_type',
      'packaging_type',
      'stock_tracking_mode',
      'default_purchase_unit',
      'default_unit',
    ]) {
      final v = row[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v.toLowerCase();
    }
    return 'kg';
  }

  Future<void> _prefetchNextHumanId() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final s = ref.read(sessionProvider);
    if (s == null) return;
    try {
      final id = await ref
          .read(hexaApiProvider)
          .nextTradePurchaseHumanId(businessId: s.primaryBusiness.id);
      if (!mounted) return;
      if (id.isNotEmpty) setState(() => _previewHumanId = id);
    } catch (_) {}
  }

  static const _draftKeyV1 = 'draft_trade_purchase_v1';

  String? _draftPrefsKey() {
    final s = ref.read(sessionProvider);
    if (s == null) return null;
    return '${_draftKeyV1}_${s.primaryBusiness.id}';
  }

  void _hideResumeDraftBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  Future<void> _maybeRestoreDraft() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    final s0 = ref.read(sessionProvider);
    if (s0 == null || k == null) return;
    final bid = s0.primaryBusiness.id;
    final fromHive = OfflineStore.getPurchaseWizardDraft(bid);
    Future<void> applyMap(Map<String, dynamic> raw) async {
      final o = Map<String, dynamic>.from(raw);
      o.remove('draftWizardMeta');
      ref.read(purchaseDraftProvider.notifier).applyFromPrefsMap(o);
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _formDirty = true);
    }

    if (fromHive != null && fromHive.isNotEmpty) {
      try {
        final o = jsonDecode(fromHive);
        if (o is Map<String, dynamic>) {
          await applyMap(o);
          if (!mounted) return;
          return;
        }
        if (o is Map) {
          await applyMap(Map<String, dynamic>.from(o));
          if (!mounted) return;
          return;
        }
      } catch (_) {}
    }

    final p = ref.read(sharedPreferencesProvider);
    final prefsStr = p.getString(k);
    if (prefsStr == null || prefsStr.isEmpty) return;
    try {
      final o = jsonDecode(prefsStr);
      if (o is! Map) return;
      final m = Map<String, dynamic>.from(o);
      await applyMap(m);
      if (!mounted) return;
      await OfflineStore.putPurchaseWizardDraft(bid, prefsStr);
      if (!mounted) return;
      await p.remove(k);
    } catch (_) {}
  }

  void _onDraftChanged() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (!mounted) return;
    if (!_formDirty) setState(() => _formDirty = true);
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _flushDraftToPrefs();
    });
  }

  Map<String, dynamic> _draftJsonForPersistence() {
    return {
      ...ref.read(purchaseDraftProvider.notifier).toPrefsMap(),
      'draftWizardMeta': {
        'savedAt': DateTime.now().toIso8601String(),
      },
    };
  }

  void _cacheDraftSnapshotForDispose() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final s = ref.read(sessionProvider);
    if (s == null) return;
    _cachedDraftBid = s.primaryBusiness.id;
    _cachedDraftPrefsKey = '${_draftKeyV1}_$_cachedDraftBid';
    _cachedDraftJson = jsonEncode(_draftJsonForPersistence());
  }

  void _flushDraftToPrefs() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    final s = ref.read(sessionProvider);
    if (s == null || k == null) return;
    final bid = s.primaryBusiness.id;
    final p = ref.read(sharedPreferencesProvider);
    final json = jsonEncode(_draftJsonForPersistence());
    _cachedDraftPrefsKey = k;
    _cachedDraftBid = bid;
    _cachedDraftJson = json;
    unawaited(p.setString(k, json));
    unawaited(OfflineStore.putPurchaseWizardDraft(bid, json));
  }

  /// Immediate save for party-step footer (still debounces on normal edits via [_onDraftChanged]).
  void _saveDraftNow() {
    _draftDebounce?.cancel();
    _flushDraftToPrefs();
    if (!mounted || widget.editingId != null) return;
    // Auto-save is silent — no snackbar distraction
  }

  Future<void> _clearDraftInPrefs() async {
    final k = _draftPrefsKey();
    final s = ref.read(sessionProvider);
    if (s == null || k == null) return;
    final bid = s.primaryBusiness.id;
    final p = ref.read(sharedPreferencesProvider);
    await p.remove(k);
    await OfflineStore.clearPurchaseWizardDraft(bid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();
    if ((widget.editingId == null || widget.editingId!.isEmpty) && _formDirty) {
      if (_cachedDraftJson == null) {
        _cacheDraftSnapshotForDispose();
      }
      final json = _cachedDraftJson;
      final key = _cachedDraftPrefsKey;
      final bid = _cachedDraftBid;
      if (json != null && key != null && bid != null) {
        unawaited(() async {
          final p = await SharedPreferences.getInstance();
          await p.setString(key, json);
          await OfflineStore.putPurchaseWizardDraft(bid, json);
        }());
      }
    }
    _partySupplierFocus.removeListener(_partyFieldFocusNotify);
    _partyBrokerFocus.removeListener(_partyFieldFocusNotify);

    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _headerDiscCtrl.dispose();
    _commissionCtrl.dispose();
    _deliveredRateCtrl.dispose();
    _billtyRateCtrl.dispose();
    _freightCtrl.dispose();
    _invoiceCtrl.dispose();
    _wizardBodyScrollController.dispose();
    _itemsStepListScrollController.dispose();
    _partySupplierFocus.dispose();
    _partyBrokerFocus.dispose();
    _termsPaymentDaysFocus.dispose();
    _termsCommissionFocus.dispose();
    _termsHeaderDiscFocus.dispose();
    _termsNarrationFocus.dispose();
    super.dispose();
  }

  String _supplierMapLabel(Map<String, dynamic> m) {
    for (final k in [
      'name',
      'legal_name',
      'display_name',
      'company_name',
      'trading_name',
    ]) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return m['id']?.toString() ?? '';
  }

  String _supplierRowId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['supplier_id'];
    return v?.toString().trim() ?? '';
  }

  DateTime? _parsePurchaseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString().trim());
  }

  Future<void> _prefetchSupplierLastPurchasesMap() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final list = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: 500,
          );
      final map = <String, DateTime>{};
      final balanceMap = <String, double>{};
      for (final p in list) {
        final sid = p['supplier_id']?.toString().trim();
        if (sid == null || sid.isEmpty) continue;
        final d = _parsePurchaseDateOnly(p['purchase_date']);

        // Only count balance for non-cancelled non-deleted purchases
        final st = p['status']?.toString().toLowerCase();
        if (st != 'cancelled' && st != 'deleted') {
          final rem = decDouble(p['remaining']);
          balanceMap[sid] = (balanceMap[sid] ?? 0) + rem;
        }

        if (d == null) continue;
        final cur = map[sid];
        if (cur == null || d.isAfter(cur)) map[sid] = d;
      }
      if (mounted) {
        setState(() {
          _supplierLastPurchaseById = map;
          _supplierBalanceById = balanceMap;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _supplierLastPurchaseById = {};
          _supplierBalanceById = {};
        });
      }
    }
  }

  List<Map<String, dynamic>> _sortSuppliersByPurchaseRecency(
    List<Map<String, dynamic>> list,
  ) {
    if (list.isEmpty) return list;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(const Duration(days: 30));
    int tier(Map<String, dynamic> m) {
      final id = _supplierRowId(m);
      final d = _supplierLastPurchaseById[id];
      if (d == null) return 2;
      final dayOnly = DateTime(d.year, d.month, d.day);
      if (!dayOnly.isBefore(cutoff)) return 0;
      return 1;
    }

    DateTime? lastDay(Map<String, dynamic> m) =>
        _supplierLastPurchaseById[_supplierRowId(m)];

    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final ta = tier(a);
      final tb = tier(b);
      if (ta != tb) return ta.compareTo(tb);
      final da = lastDay(a);
      final db = lastDay(b);
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return _supplierMapLabel(a)
          .toLowerCase()
          .compareTo(_supplierMapLabel(b).toLowerCase());
    });
    return sorted;
  }

  String _supplierSearchSubtitle(Map<String, dynamic> m) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(const Duration(days: 30));
    final id = _supplierRowId(m);
    final d = _supplierLastPurchaseById[id];
    if (d != null) {
      final dayOnly = DateTime(d.year, d.month, d.day);
      if (!dayOnly.isBefore(cutoff)) {
        return 'Last: ${DateFormat('dd MMM yyyy').format(d)}';
      }
    }
    final phone = m['phone']?.toString().trim();
    if (phone != null && phone.isNotEmpty) return phone;
    final gst = m['gst_number']?.toString().trim();
    if (gst != null && gst.isNotEmpty) return gst;
    return '';
  }

  void _partyStepSnack(String message) {
    if (!mounted) return;
    showTopSnack(context, message);
  }

  void _reportWizardNonFatal(String context, Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'purchase_entry_wizard_v2',
        context: ErrorDescription(context),
      ),
    );
  }

  Future<void> _openQuickSupplierCreate(
    List<Map<String, dynamic>> lookupList,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    Map<String, dynamic>? result;
    try {
      result = await Navigator.of(context, rootNavigator: true)
          .push<Map<String, dynamic>?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const SupplierCreateSimple(),
        ),
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      _partyStepSnack(
        'Could not open the new supplier form. ${userFacingError(e)}',
      );
      return;
    }
    if (!mounted) return;
    final id = result?['id']?.toString();
    if (id == null || id.isEmpty) {
      _partyStepSnack(
        result == null
            ? 'New supplier cancelled.'
            : 'Supplier not saved (missing id). Fill required fields and save.',
      );
      return;
    }
    final label = (result?['name']?.toString() ?? '').trim();
    final disp = label.isNotEmpty ? label : 'Supplier';
    final item = InlineSearchItem(id: id, label: disp);
    unawaited(_applySupplierSelectionAsync(const [], item));
    if (mounted) setState(() => _partyUserSupplierActionGeneration++);
    Future.microtask(() {
      if (mounted) ref.invalidate(suppliersListProvider);
    });
  }

  Future<void> _openQuickBrokerCreate(
    List<Map<String, dynamic>> lookupList,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    Map<String, dynamic>? result;
    try {
      result = await Navigator.of(context, rootNavigator: true)
          .push<Map<String, dynamic>?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              const BrokerWizardPage(selectionReturnOnSave: true),
        ),
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (!mounted) return;
      _partyStepSnack(
        'Could not open the new broker form. ${userFacingError(e)}',
      );
      return;
    }
    if (!mounted) return;
    final id = result?['id']?.toString();
    if (id == null || id.isEmpty) {
      _partyStepSnack(
        result == null
            ? 'New broker cancelled.'
            : 'Broker not saved (missing id). Fill required fields and save.',
      );
      return;
    }
    final label = (result?['name']?.toString() ?? '').trim();
    final disp = label.isNotEmpty ? label : 'Broker';
    unawaited(_applyBrokerSelectionAsync(InlineSearchItem(id: id, label: disp)));
    Future.microtask(() {
      if (mounted) ref.invalidate(brokersListProvider);
    });
  }

  void _applyHeaderDefaultsFromLastTrade(Map<String, dynamic> d) {
    final notifier = ref.read(purchaseDraftProvider.notifier);
    final pdays = d['payment_days'];
    if (pdays is num && pdays.toInt() >= 0) {
      notifier.setPaymentDaysText('${pdays.toInt()}');
    }
    final brid = d['broker_id']?.toString().trim();
    if (brid != null && brid.isNotEmpty) {
      final brokers = ref.read(brokersListProvider).valueOrNull ?? const [];
      var bn = 'Broker';
      for (final b in brokers) {
        if (b['id']?.toString() == brid) {
          bn = b['name']?.toString() ?? bn;
          break;
        }
      }
      notifier.setBroker(brid, bn, fromSupplier: false);
    }
    _syncControllersFromDraft();
    if (mounted) setState(() {});
  }

  /// that has a catalog item with non-empty defaults. If any such line has no defaults,
  /// fall back to the full list. Empty intersection falls back to full list.
  List<Map<String, dynamic>> _filterSuppliersByCatalogLineDefaults(
    List<Map<String, dynamic>> allSuppliers,
    List<Map<String, dynamic>> catalog,
  ) {
    final draft = ref.read(purchaseDraftProvider);
    Set<String>? allowed;
    for (final line in draft.lines) {
      final cid = line.catalogItemId;
      if (cid == null || cid.isEmpty) continue;
      Map<String, dynamic>? item;
      for (final c in catalog) {
        if (c['id']?.toString() == cid) {
          item = c;
          break;
        }
      }
      if (item == null) continue;
      final raw = item['default_supplier_ids'] as List?;
      if (raw == null || raw.isEmpty) {
        allowed = null;
        break;
      }
      final sset = raw.map((e) => e.toString()).toSet();
      allowed = allowed == null ? sset : allowed.intersection(sset);
    }
    if (allowed == null) return allSuppliers;
    if (allowed.isEmpty) return allSuppliers;
    final allow = allowed;
    final filtered =
        allSuppliers.where((m) => allow.contains(_supplierRowId(m))).toList();
    return filtered.isEmpty ? allSuppliers : filtered;
  }

  void _applySupplierSelection(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) {
    unawaited(_applySupplierSelectionAsync(list, it));
  }

  Future<void> _applySupplierSelectionAsync(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) async {
    if (it.id.isEmpty) return;
    final seq = ++_supplierApplySeq;
    final want = it.id.trim().toLowerCase();
    Map<String, dynamic>? row;
    for (final m in list) {
      if (_supplierRowId(m).toLowerCase() == want) {
        row = Map<String, dynamic>.from(m);
        break;
      }
    }
    row ??= <String, dynamic>{'id': it.id, 'name': it.label};
    final session = ref.read(sessionProvider);

    // Commit draft immediately so a tap cannot be wiped by overlapping async / seq churn.
    final commitRow = Map<String, dynamic>.from(row);
    if (mounted && seq == _supplierApplySeq) {
      ref
          .read(purchaseDraftProvider.notifier)
          .applySupplierSelection(commitRow, it.id, it.label);
      unawaited(PurchaseSmartDefaults.saveLastSupplierId(it.id));
      _syncControllersFromDraft();
      setState(() {
        _supplierFieldError = null;
        _brokerFieldError = null;
        _inlineSaveError = null;
      });
      _onDraftChanged();
    }

    if (session != null) {
      try {
        final fresh = await ref.read(hexaApiProvider).getSupplier(
              businessId: session.primaryBusiness.id,
              supplierId: it.id,
            );
        if (fresh.isNotEmpty) {
          row = fresh;
        }
      } catch (e, st) {
        _reportWizardNonFatal('getSupplier after supplier selection', e, st);
      }
    }
    if (!mounted || seq != _supplierApplySeq) return;
    final supplierRow = row!;
    // Re-apply after possible fresh master row fetch (still same selection).
    ref
        .read(purchaseDraftProvider.notifier)
        .applySupplierSelection(supplierRow, it.id, it.label);
    if (session != null) {
      try {
        final autofill =
            await ref.read(hexaApiProvider).tradeLastSupplierAutofill(
                  businessId: session.primaryBusiness.id,
                  supplierId: it.id,
                );
        if (!mounted || seq != _supplierApplySeq) return;
        final src = autofill['source']?.toString();
        final abid = autofill['broker_id']?.toString().trim();
        if (abid != null && abid.isNotEmpty) {
          try {
            final b = await ref.read(hexaApiProvider).getBroker(
                  businessId: session.primaryBusiness.id,
                  brokerId: abid,
                );
            if (!mounted || seq != _supplierApplySeq) return;
            final nm = b['name']?.toString().trim();
            ref.read(purchaseDraftProvider.notifier).setBroker(
                  abid,
                  (nm != null && nm.isNotEmpty) ? nm : 'Broker',
                  fromSupplier: false,
                );
            if (b.isNotEmpty) {
              ref
                  .read(purchaseDraftProvider.notifier)
                  .applyBrokerDealDefaults(b);
            }
          } catch (e, st) {
            _reportWizardNonFatal('getBroker during supplier autofill', e, st);
            if (!mounted || seq != _supplierApplySeq) return;
            ref.read(purchaseDraftProvider.notifier).setBroker(
                  abid,
                  'Broker',
                  fromSupplier: false,
                );
          }
        } else if (src == 'supplier_last_trade') {
          ref.read(purchaseDraftProvider.notifier).setBroker(null, null);
        }
      } catch (e, st) {
        _reportWizardNonFatal('tradeLastSupplierAutofill', e, st);
      }
    }
    if (!mounted || seq != _supplierApplySeq) return;
    _syncControllersFromDraft();
    setState(() {
      _supplierFieldError = null;
      _brokerFieldError = null;
      _inlineSaveError = null;
    });
    _onDraftChanged();
    HapticFeedback.selectionClick();
    unawaited(_openCatalogLinePrefillIfNeeded());
  }

  String _brokerRowId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['broker_id'];
    return v?.toString().trim() ?? '';
  }

  String _brokerMapLabel(Map<String, dynamic> m) {
    final v = m['name']?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return _brokerRowId(m);
  }

  void _applyBrokerSelection(InlineSearchItem it) {
    unawaited(_applyBrokerSelectionAsync(it));
  }

  void _onUserSupplierSelected(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) {
    // Commit draft first (sync portion of async apply), then bump generation so a
    // rebuild never runs between "empty" and "picked" in a way that drops the selection.
    _applySupplierSelection(list, it);
    if (mounted) setState(() => _partyUserSupplierActionGeneration++);
  }

  Future<void> _applyBrokerSelectionAsync(InlineSearchItem it) async {
    if (it.id.isEmpty) return;
    ref.read(purchaseDraftProvider.notifier).setBroker(
          it.id,
          it.label,
          fromSupplier: false,
        );
    final session = ref.read(sessionProvider);
    if (session != null) {
      try {
        final b = await ref.read(hexaApiProvider).getBroker(
              businessId: session.primaryBusiness.id,
              brokerId: it.id,
            );
        if (!mounted) return;
        if (b.isNotEmpty) {
          ref.read(purchaseDraftProvider.notifier).applyBrokerDealDefaults(b);
        }
      } catch (e, st) {
        _reportWizardNonFatal('getBroker after broker selection', e, st);
      }
    }
    if (!mounted) return;
    _syncControllersFromDraft();
    setState(() {
      _brokerFieldError = null;
      _inlineSaveError = null;
    });
    _onDraftChanged();
    HapticFeedback.selectionClick();
  }

  Future<void> _learnCatalogPackDefaultsIfNeeded(
    List<Map<String, dynamic>> catalogRows,
    PurchaseLineDraft line,
  ) async {
    final id = (line.catalogItemId ?? '').trim();
    if (id.isEmpty) return;
    final kpu = line.kgPerUnit;
    if (kpu == null || kpu <= 0) return;
    final u = line.unit.trim().toLowerCase();
    if (u != 'bag' && u != 'sack') return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    Map<String, dynamic>? row;
    for (final r in catalogRows) {
      if (r['id']?.toString() == id) {
        row = r;
        break;
      }
    }
    final raw = row == null
        ? null
        : (row['default_kg_per_bag'] ??
            row['kg_per_bag'] ??
            row['kg_per_unit']);
    final catalogKpb = coerceToDoubleNullable(raw);
    if (catalogKpb != null && (catalogKpb - kpu).abs() < 0.05) return;
    try {
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
            patchDefaultKgPerBag: true,
            defaultKgPerBag: kpu,
            includeDefaultUnit: true,
            defaultUnit: 'bag',
          );
      if (!mounted) return;
      ref.invalidate(catalogItemsListProvider);
    } catch (_) {}
  }

  void _scrollWizardItemsStepToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void animate(ScrollController c) {
          if (!c.hasClients) return;
          final pos = c.position;
          if (pos.maxScrollExtent <= 0) return;
          c.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }

        if (_wizStep == 1) {
          animate(_itemsStepListScrollController);
        } else {
          animate(_wizardBodyScrollController);
        }
      });
    });
  }

  Future<void> _openItemSheet(
    List<Map<String, dynamic>> catalog, {
    int? editIndex,
    Map<String, dynamic>? initialOverride,
  }) async {
    final draft = ref.read(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Select a supplier on the Party step before adding items.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    _hideResumeDraftBanner();
    final session = ref.read(sessionProvider);
    var catalogForSheet = List<Map<String, dynamic>>.from(catalog);
    if (catalogForSheet.isEmpty) {
      try {
        final loaded = await ref.read(catalogItemsListProvider.future);
        catalogForSheet = List<Map<String, dynamic>>.from(loaded);
      } catch (_) {}
    }
    if (!mounted) return;
    if (catalogForSheet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Catalog is still loading. Wait a moment and try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final initial = initialOverride ??
        (editIndex != null
            ? ref.read(purchaseDraftProvider).lines[editIndex].toLineMap()
            : null);
    // Ensure the sheet can resolve `default_kg_per_bag` for this line (list may omit the row).
    final cid = initial?['catalog_item_id']?.toString();
    if (cid != null && cid.isNotEmpty) {
      final has = catalogForSheet.any((m) => m['id']?.toString() == cid);
      if (!has) {
        if (session != null) {
          try {
            final row = await ref.read(hexaApiProvider).getCatalogItem(
                  businessId: session.primaryBusiness.id,
                  itemId: cid,
                );
            if (row.isNotEmpty) {
              catalogForSheet = [
                Map<String, dynamic>.from(row),
                ...catalogForSheet
              ];
            }
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    final supplierId = draft.supplierId?.trim();
    final priorityIds = supplierId != null && supplierId.isNotEmpty
        ? await _recentCatalogItemIdsForSupplier(supplierId)
        : const <String>[];
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => PurchaseItemEntrySheet(
          catalog: catalogForSheet,
          initial: initial,
          isEdit: editIndex != null,
          fullPage: true,
          gstPrefs: ref.read(sharedPreferencesProvider),
          preferredSupplierId:
              supplierId != null && supplierId.isNotEmpty ? supplierId : null,
          priorityCatalogItemIds: priorityIds,
          omitLineFreightDeliveredBilltyDiscount: false,
          navigateCatalogQuickAddItem: session == null
              ? null
              : () async {
                  final supId = draft.supplierId?.trim();
                  final broId = draft.brokerId?.trim();
                  final q = <String, String>{
                    if (supId != null && supId.isNotEmpty)
                      'defaultSupplierId': supId,
                    if (broId != null && broId.isNotEmpty)
                      'defaultBrokerId': broId,
                    'returnToPurchase': '1',
                  };
                  final uri = Uri(
                    path: '/catalog/quick-add',
                    queryParameters: q.isEmpty ? null : q,
                  );
                  final res = await ctx.push<Map<String, dynamic>?>(uri.toString());
                  if (!ctx.mounted) return null;
                  if (res != null &&
                      (res['id']?.toString().trim().isNotEmpty ?? false)) {
                    ref.invalidate(catalogItemsListProvider);
                    try {
                      await ref.read(catalogItemsListProvider.future);
                    } catch (_) {}
                  }
                  return res;
                },
          onDefaultsResolved: session == null
              ? null
              : _applyHeaderDefaultsFromLastTrade,
          resolveCatalogItem: session == null
              ? null
              : (String catalogItemId) =>
                  ref.read(hexaApiProvider).getCatalogItem(
                        businessId: session.primaryBusiness.id,
                        itemId: catalogItemId,
                      ),
          resolveLastDefaults: session == null
              ? null
              : (String catalogItemId) {
                  final d = ref.read(purchaseDraftProvider);
                  return ref.read(hexaApiProvider).lastTradePurchaseDefaults(
                        businessId: session.primaryBusiness.id,
                        catalogItemId: catalogItemId,
                        supplierId: d.supplierId,
                        brokerId: d.brokerId,
                      );
                },
          persistCatalogBagWeight: session == null
              ? null
              : ({
                  required String catalogItemId,
                  required String newName,
                  required double defaultKgPerBag,
                }) async {
                  await ref.read(hexaApiProvider).updateCatalogItem(
                        businessId: session.primaryBusiness.id,
                        itemId: catalogItemId,
                        name: newName,
                        patchDefaultKgPerBag: true,
                        defaultKgPerBag: defaultKgPerBag,
                        includeDefaultUnit: true,
                        defaultUnit: 'bag',
                      );
                  ref.invalidate(catalogItemsListProvider);
                },
          onCommitted: (line) {
            final p = PurchaseLineDraft.fromLineMap(
              Map<String, dynamic>.from(line),
            );
            ref.read(purchaseDraftProvider.notifier).addOrReplaceLine(
                  p,
                  editIndex: editIndex,
                );
            setState(() {
              _inlineSaveError = null;
              _lineJustAdded = p;
            });
            _onDraftChanged();
            unawaited(_learnCatalogPackDefaultsIfNeeded(catalogForSheet, p));
          },
        ),
      ),
    );
    if (mounted && _wizStep == 1) {
      _scrollWizardItemsStepToBottom();
    }
  }

  bool _isEditMode() =>
      widget.editingId != null && widget.editingId!.isNotEmpty;

  Future<void> _discardDraftAndPop() async {
    ref.read(purchaseDraftProvider.notifier).reset();
    await _clearDraftInPrefs();
    if (!mounted) return;
    setState(() => _formDirty = false);
    context.popOrGo('/purchase');
  }

  Future<void> _handleWizardExitFromRoot() async {
    if (_isEditMode()) {
      context.popOrGo('/purchase');
      return;
    }
    if (!_formDirty) {
      context.popOrGo('/purchase');
      return;
    }
    final choice = await showCupertinoDialog<_WizardExitDraftChoice>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Save your progress?'),
        content: const Text(
          'You have an unsaved purchase draft. Save it locally, discard it, or keep editing.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () =>
                popOverlay(ctx, _WizardExitDraftChoice.keepEditing),
            child: const Text('Keep editing'),
          ),
          CupertinoDialogAction(
            onPressed: () =>
                popOverlay(ctx, _WizardExitDraftChoice.saveDraft),
            child: const Text('Save draft'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () =>
                popOverlay(ctx, _WizardExitDraftChoice.discard),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _WizardExitDraftChoice.keepEditing) return;
    if (choice == _WizardExitDraftChoice.saveDraft) {
      _saveDraftNow();
      context.popOrGo('/purchase');
      return;
    }
    await _discardDraftAndPop();
  }

  Future<void> _wizBack() async {
    FocusScope.of(context).unfocus();
    if (_wizStep > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _wizStep -= 1);
      });
      return;
    }
    if (!mounted) return;
    await _handleWizardExitFromRoot();
  }

  bool _isDuplicatePurchase409(DioException e) {
    if (e.response?.statusCode != 409) return false;
    final data = e.response?.data;
    if (data is! Map) return false;
    final detail = data['detail'];
    return detail is Map &&
        detail['code']?.toString() == 'DUPLICATE_PURCHASE_DETECTED';
  }

  /// Shows delivery prompt on the next frame (avoids scheduling modals mid-build).
  Future<void> _scheduleDeliveryPrompt(String purchaseId) async {
    if (purchaseId.isEmpty) return;
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        if (!done.isCompleted) done.complete();
        return;
      }
      await _showDeliveryPrompt(purchaseId);
      if (!done.isCompleted) done.complete();
    });
    await done.future;
  }

  Future<void> _showDeliveryPrompt(String purchaseId) async {
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    // business id is already available from session; keep local only when needed

    final delivered = await showHexaBottomSheet<bool>(
      context: context,
      compact: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 40,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          const Text(
            'Has this shipment arrived at your warehouse?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not Yet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Yes, Received'),
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (delivered == true && mounted) {
      showTopSnack(
        context,
        'Purchase saved — warehouse will receive and verify separately',
      );
    }
  }

  String? _purchaseCreatorDisplayName(Map<String, dynamic> saved) {
    for (final k in ['created_by_name', 'user_name', 'staff_name']) {
      final v = saved[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return ref.read(sessionProvider)?.primaryBusiness.name;
  }

  TradePurchase _tradePurchaseFromSaved(
    Map<String, dynamic> saved,
    PurchaseDraft draftSnap,
  ) {
    final merged = enrichSavedTradePurchaseJson(
      saved,
      supplierNameFallback: draftSnap.supplierName,
      brokerNameFallback: draftSnap.brokerName,
      purchaseDateFallback: draftSnap.purchaseDate,
    );
    return TradePurchase.fromJson(merged);
  }

  Future<void> _shareToAccountsWhatsapp({
    required Map<String, dynamic> saved,
    required PurchaseDraft draftSnap,
  }) async {
    final p = _tradePurchaseFromSaved(saved, draftSnap);
    final biz = ref.read(invoiceBusinessProfileProvider);
    final phone = normalizedFromStoredAccountsWhatsapp(biz.accountsWhatsappNumber) ??
        normalizeAccountsWhatsappPhone(biz.accountsWhatsappNumber);
    final pdfResult = await sharePurchaseToAccountsStaff(
      p,
      biz,
      generatedByName: _purchaseCreatorDisplayName(saved),
    );
    final pid = saved['id']?.toString() ?? '';
    final hid = saved['human_id']?.toString();
    unawaited(
      StaffActivityLogger.logPurchaseWhatsappShare(
        ref,
        purchaseId: pid,
        success: pdfResult.ok,
        humanId: hid,
        recipientMasked:
            phone != null ? maskWhatsappRecipient(phone.waMeDigits) : null,
        errorMessage: pdfResult.ok ? null : pdfResult.message,
      ),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (pdfResult.ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Purchase saved. Shared to accounts WhatsApp.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Purchase saved successfully. WhatsApp delivery failed.',
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Retry Send',
            onPressed: () {
              unawaited(
                _shareToAccountsWhatsapp(saved: saved, draftSnap: draftSnap),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _validateAndSave({bool shareAfterSave = false}) async {
    if (_isSaving) return;
    setState(() {
      _inlineSaveError = null;
      _supplierFieldError = null;
      _brokerFieldError = null;
    });
    final v = ref.read(purchaseSaveValidationProvider);
    if (!v.isOk) {
      if (v.errorMessage != null) {
        final msg = v.errorMessage!.toLowerCase();
        final isSupplier = msg.contains('supplier');
        final isBroker = msg.contains('broker');
        if (isSupplier) {
          setState(() {
            _supplierFieldError = v.errorMessage;
            _brokerFieldError = null;
            _inlineSaveError = null;
            _wizStep = 0;
          });
        } else if (isBroker) {
          setState(() {
            _brokerFieldError = v.errorMessage;
            _supplierFieldError = null;
            _inlineSaveError = null;
            _wizStep = 0;
          });
        } else {
          setState(() {
            _inlineSaveError = v.errorMessage;
            _supplierFieldError = null;
            _brokerFieldError = null;
            _wizStep = 2;
          });
        }
      } else if (v.lineErrors.isNotEmpty) {
        final first = v.lineErrors.values.first;
        setState(() {
          _inlineSaveError = first;
          _supplierFieldError = null;
          _brokerFieldError = null;
          _wizStep = 1;
        });
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm purchase save?'),
        content: Text(
          shareAfterSave
              ? (_isEditMode()
                  ? 'Save changes and share PDF + summary to accounts WhatsApp?'
                  : 'Save and share purchase PDF + summary to accounts WhatsApp?')
              : (_isEditMode()
                  ? 'Save changes to this purchase?'
                  : 'Saving will submit this purchase to your records. Continue?'),
        ),
        actions: [
          TextButton(
            onPressed: () => popOverlay(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => popOverlay(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    HapticFeedback.mediumImpact();
    await _savePurchaseAttempt(
      forceDuplicate: false,
      shareAfterSave: shareAfterSave,
    );
  }

  bool _aiScanWarningsBlock(Map<String, dynamic> scan) {
    final w = scan['warnings'];
    if (w is! List) return false;
    for (final e in w) {
      if (e is! Map) continue;
      final sev = e['severity']?.toString().toLowerCase();
      if (sev == 'block' || sev == 'blocker') return true;
    }
    return false;
  }

  String _formatTradeValidateErrors(Map<String, dynamic> val) {
    final errs = val['errors'];
    if (errs is! List || errs.isEmpty) {
      return 'Purchase did not pass server validation.';
    }
    final parts = <String>[];
    for (final e in errs.take(8)) {
      if (e is Map) {
        final loc = e['loc'];
        String? lineHint;
        if (loc is List &&
            loc.length >= 3 &&
            (loc[2] is int || loc[2] is num)) {
          final idx = (loc[2] is int) ? loc[2] as int : (loc[2] as num).toInt();
          lineHint = 'Line ${idx + 1}: ';
        }
        final m = e['message']?.toString() ??
            e['detail']?.toString() ??
            e['msg']?.toString();
        if (m != null && m.trim().isNotEmpty) {
          parts.add('${lineHint ?? ''}${m.trim()}');
        }
      } else if (e != null && e.toString().trim().isNotEmpty) {
        parts.add(e.toString().trim());
      }
    }
    return parts.isEmpty ? 'Purchase did not pass server validation.' : parts.join('; ');
  }

  Future<bool> _runServerTradeValidate(String bid, Map<String, dynamic> body) async {
    try {
      final val = await ref.read(hexaApiProvider).validateTradePurchase(
            businessId: bid,
            body: body,
          );
      if (val['ok'] == true) return true;
      if (mounted) {
        setState(() {
          _isSaving = false;
          _inlineSaveError = _formatTradeValidateErrors(val);
          _wizStep = 2;
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _inlineSaveError =
              'Could not validate purchase with the server. Check your connection.';
          _wizStep = 2;
        });
      }
      return false;
    }
  }

  Future<void> _savePurchaseAttempt({
    required bool forceDuplicate,
    bool shareAfterSave = false,
  }) async {
    if (_isSaving) return;
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Not signed in'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _isSaving = true);
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    final body =
        ref.read(purchaseDraftProvider.notifier).buildTradePurchaseBody(
              forceDuplicate: forceDuplicate,
            );
    final isEdit = _isEditMode();

    if (kDebugMode) {
      final d = ref.read(purchaseDraftProvider);
      debugPrint(
        '[PurchaseWizard] submit supplier id=${d.supplierId} name="${d.supplierName}"',
      );
      debugPrint(
        '[PurchaseWizard] submit broker id=${d.brokerId} name="${d.brokerName}"',
      );
      final lines = d.lines;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        debugPrint(
          '[PurchaseWizard] line[$i] catalogId=${l.catalogItemId} name="${l.itemName}"',
        );
      }
      debugPrint('[PurchaseWizard] submit body: $body');
    }

    try {
      Map<String, dynamic> saved;
      final aiToken = widget.aiScanToken?.trim();
      final aiBase = widget.aiScanBaseJson;
      if (!isEdit &&
          aiToken != null &&
          aiToken.isNotEmpty &&
          aiBase != null) {
        final d = ref.read(purchaseDraftProvider);
        final merged = scanResultJsonMergePurchaseDraft(
          Map<String, dynamic>.from(aiBase),
          d,
        );
        final blocker = _aiScanWarningsBlock(aiBase);
        if (!scanDraftReadyForCreate(merged, scanIssueBlocker: blocker)) {
          if (mounted) {
            setState(() {
              _isSaving = false;
              _inlineSaveError =
                  'Match supplier and catalog items with rates for every line before saving this scan.';
              _wizStep = 1;
            });
          }
          return;
        }
        final tradeBody = ref
            .read(purchaseDraftProvider.notifier)
            .buildTradePurchaseBody(forceDuplicate: forceDuplicate);
        if (!await _runServerTradeValidate(bid, tradeBody)) return;
        if (!mounted) return;
        final forceDup = tradeBody['force_duplicate'] == true;
        final pd = d.purchaseDate ?? DateTime.now();
        saved = await scanPurchaseUpdateAndConfirm(
          ref: ref,
          scanToken: aiToken,
          scanPayload: merged,
          purchaseDate: pd,
          invoiceNumber: d.invoiceNumber,
          forceDuplicate: forceDup,
        );
        if (!mounted) return;
      } else if (isEdit) {
        if (!await _runServerTradeValidate(bid, body)) return;
        if (!mounted) return;
        saved = await api.updateTradePurchase(
              businessId: bid,
              purchaseId: widget.editingId!,
              body: body,
            );
      } else {
        if (!await _runServerTradeValidate(bid, body)) return;
        if (!mounted) return;
        saved = await api.createTradePurchase(
              businessId: bid,
              body: body,
            );
      }
      if (!mounted) return;
      final draftSnap = ref.read(purchaseDraftProvider);
      final savedItemIds = catalogItemIdsFromTradeJson(saved);
      invalidatePurchaseWorkspace(ref, affectedItemIds: savedItemIds);
      ref.invalidate(stockAuditPeriodProvider);
      final committed =
          (saved['delivery_status']?.toString() ?? '').toLowerCase() ==
              'stock_committed';
      final stockUpdates = saved['stock_updates'] as List? ?? const [];
      final pidForStock = saved['id']?.toString() ?? '';
      if (pidForStock.isNotEmpty &&
          (committed || stockUpdates.isNotEmpty)) {
        if (committed) {
          invalidateAfterDeliveryCommit(
            ref,
            purchaseId: pidForStock,
            affectedItemIds: savedItemIds,
          );
        } else {
          syncPurchaseStockFromPurchaseJson(
            ref,
            purchaseId: pidForStock,
            body: saved,
          );
        }
      }
      for (final line in draftSnap.lines) {
        final itemId = line.catalogItemId?.trim();
        if (itemId == null || itemId.isEmpty) continue;
        ref.invalidate(catalogItemDetailProvider(itemId));
        ref.invalidate(stockItemIntelligenceProvider(itemId));
      }
      ref.read(purchaseDraftProvider.notifier).reset();
      await _clearDraftInPrefs();
      if (!mounted) return;
      _syncControllersFromDraft();
      if (mounted) {
        setState(() {
          _isSaving = false;
          _formDirty = false;
          _partyUserSupplierActionGeneration++;
        });
      }
      final pid = saved['id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        unawaited(LocalNotificationsService.instance
            .scheduleTradePurchaseDueAtNineAmIfNeeded(
          purchaseId: pid,
          dueDateIso: saved['due_date']?.toString(),
          humanId: saved['human_id']?.toString(),
        ));
        final hm = saved['has_missing_details'] == true ||
            saved['has_missing_details']?.toString().toLowerCase() == 'true';
        if (hm) {
          unawaited(LocalNotificationsService.instance
              .schedulePurchaseMissingDetailsReminder(
            purchaseId: pid,
            humanId: saved['human_id']?.toString(),
          ));
        } else {
          unawaited(LocalNotificationsService.instance
              .cancelPurchaseMissingDetailsReminder(pid));
        }
        if (ref.read(localNotificationsOptInProvider)) {
          final hid = saved['human_id']?.toString();
          final label =
              (hid != null && hid.isNotEmpty) ? hid : pid;
          final amount = saved['total_amount'] ?? saved['net_amount'];
          String? totalStr;
          if (amount != null) {
            totalStr = formatRupee(decDouble(amount));
          }
          unawaited(LocalNotificationsService.instance.showPurchaseSaved(
            humanId: label,
            totalFormatted: totalStr,
          ));
        }
        unawaited(StaffActivityLogger.logPurchase(ref, saved));
      }
      if (!mounted) return;
      if (shareAfterSave && pid.isNotEmpty) {
        if (!ref.read(autoSharePurchaseWhatsappProvider)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Purchase saved. Turn on auto WhatsApp share in Settings to send on Save & Share.',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          final configured =
              await ensureAccountsWhatsappConfigured(context, ref);
          if (configured && mounted) {
            await _shareToAccountsWhatsapp(
              saved: saved,
              draftSnap: draftSnap,
            );
          }
        }
      }
      if (!mounted) return;
      final quick = ref.read(quickSavePurchaseProvider);
      if (quick) {
        if (!shareAfterSave) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isEdit
                    ? 'Purchase updated · history refreshed'
                    : 'Purchase saved · history refreshed',
              ),
              backgroundColor: Colors.green[700],
            ),
          );
        }
        if (!isEdit && pid.isNotEmpty) {
          await _scheduleDeliveryPrompt(pid);
        }
        if (!mounted) return;
        context.popOrGo('/purchase');
      } else {
        final where = await showPurchaseSavedSheet(
          context,
          ref,
          savedJson: saved,
          wasEdit: isEdit,
          displaySupplierName: draftSnap.supplierName,
          displayBrokerName: draftSnap.brokerName,
          displayPurchaseDate: draftSnap.purchaseDate,
        );
        if (!mounted) return;
        if (!isEdit && pid.isNotEmpty) {
          await _scheduleDeliveryPrompt(pid);
        }
        if (!mounted) return;
        if (where == 'add_more') {
          ref.read(purchaseDraftProvider.notifier).reset();
          _syncControllersFromDraft();
          setState(() {
            _wizStep = 0;
            _lineJustAdded = null;
            _formDirty = false;
            _inlineSaveError = null;
            _supplierFieldError = null;
            _brokerFieldError = null;
            _partyUserSupplierActionGeneration++;
            _didAutoFocusPartyFromAiScan = false;
            _didAutoFocusBrokerFromAiScan = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            FocusScope.of(context).requestFocus(_partySupplierFocus);
          });
          return;
        }
        if (where == 'edit_missing') {
          final id = saved['id']?.toString();
          if (id != null && id.isNotEmpty) {
            context.push('/purchase/edit/$id');
          } else {
            context.popOrGo('/purchase');
          }
          return;
        }
        if (where == 'later_missing') {
          context.popOrGo('/purchase');
          return;
        }
        if (where == 'detail') {
          final id = saved['id']?.toString();
          if (id != null && id.isNotEmpty) {
            TradePurchase? seed;
            try {
              seed = TradePurchase.fromJson(Map<String, dynamic>.from(saved));
            } catch (_) {}
            context.go('/purchase/detail/$id', extra: seed);
          }
        } else {
          context.popOrGo('/purchase');
        }
      }
    } on DioException catch (e) {
      // Offline-first: queue NEW purchase creates on connectivity failures.
      final t = e.type;
      final isNetwork = t == DioExceptionType.connectionError ||
          t == DioExceptionType.connectionTimeout ||
          t == DioExceptionType.sendTimeout ||
          t == DioExceptionType.receiveTimeout;
      if (!isEdit && isNetwork) {
        try {
          final fingerprint =
              OfflineSyncService.fingerprintForTradePurchaseCreate(body);
          await OfflineStore.queueEntry({
            'kind': 'trade_purchase_create',
            'businessId': bid,
            'fingerprint': fingerprint,
            'body': body,
          });
        } catch (_) {}
        ref.read(purchaseDraftProvider.notifier).reset();
        await _clearDraftInPrefs();
        _syncControllersFromDraft();
        if (mounted) {
          setState(() {
            _isSaving = false;
            _formDirty = false;
            _inlineSaveError = null;
            _supplierFieldError = null;
            _brokerFieldError = null;
            _partyUserSupplierActionGeneration++;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Saved offline — will sync automatically'),
              backgroundColor: Colors.blueGrey[700],
            ),
          );
          context.popOrGo('/purchase');
        }
        return;
      }
      if (!forceDuplicate && _isDuplicatePurchase409(e)) {
        if (mounted) {
          setState(() => _isSaving = false);
        }
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar purchase already exists'),
            content: const Text(
              'A purchase that looks like this is already recorded for this date. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => popOverlay(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => popOverlay(ctx, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (proceed == true && mounted) {
          await _savePurchaseAttempt(
            forceDuplicate: true,
            shareAfterSave: shareAfterSave,
          );
        }
        return;
      }
      if (mounted) {
        final hint = fastApiPurchaseScrollHint(e.response?.data);
        final msg = friendlyApiError(e);
        setState(() {
          _isSaving = false;
          if (hint != null && hint.supplierField) {
            _wizStep = 0;
            _supplierFieldError = msg;
            _brokerFieldError = null;
            _inlineSaveError = null;
          } else if (hint != null && hint.brokerField) {
            _wizStep = 0;
            _brokerFieldError = msg;
            _supplierFieldError = null;
            _inlineSaveError = null;
          } else if (hint != null && hint.lineIndex != null) {
            _wizStep = 1;
            _supplierFieldError = null;
            _brokerFieldError = null;
            _inlineSaveError = msg;
          } else {
            _supplierFieldError = null;
            _brokerFieldError = null;
            _inlineSaveError = msg;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _inlineSaveError = friendlyApiError(e);
        });
      }
    }
  }

  void _partyAdvanceIfValid() {
    final d = ref.read(purchaseDraftProvider);
    final hasS = d.supplierId != null && d.supplierId!.trim().isNotEmpty;
    setState(() => _inlineSaveError = null);
    if (!hasS) {
      setState(() {
        _supplierFieldError = 'Select a supplier.';
        _brokerFieldError = null;
      });
      return;
    }
    setState(() {
      _supplierFieldError = null;
      _brokerFieldError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _termsPaymentDaysFocus.requestFocus();
      if (_wizardBodyScrollController.hasClients) {
        final pos = _wizardBodyScrollController.position;
        if (pos.maxScrollExtent > 0) {
          _wizardBodyScrollController.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _autoSelectCommissionUnitFromLinesIfNeeded() {
    final draft = ref.read(purchaseDraftProvider);
    final lines = draft.lines;

    // On the combined party+terms step there may be zero lines until items.
    // there may be zero lines. Only auto-select when lines actually exist.
    if (lines.isEmpty) return;

    // Only auto-set if the user hasn't already chosen a fixed-₹ basis.
    final current = (draft.commissionMode).trim().toLowerCase();
    if (current.isNotEmpty && current != kPurchaseCommissionModePercent) return;

    final suggested = suggestedBrokerFigureModeFromLines(lines);
    ref.read(purchaseDraftProvider.notifier).setCommissionMode(suggested);
  }

  void _wizNext() {
    // [Bug 3] Validate the current step on press; show the precise missing
    // field instead of silently disabling the button.
    if (_wizStep != 0) {
      FocusScope.of(context).unfocus();
    }
    final reasons = ref.read(purchaseStepBlockReasonsProvider);
    setState(() => _inlineSaveError = null);
    if (_wizStep == 0) {
      if (reasons.from0 != null) {
        setState(() {
          _supplierFieldError = reasons.from0;
          _inlineSaveError = reasons.from0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _partySupplierFocus.requestFocus();
        });
        return;
      }
      if (reasons.from1 != null) {
        setState(() {
          _inlineSaveError = reasons.from1;
          _supplierFieldError = null;
          _brokerFieldError = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _termsPaymentDaysFocus.requestFocus();
        });
        return;
      }
      setState(() {
        _supplierFieldError = null;
        _brokerFieldError = null;
        _lineJustAdded = null;
        _wizStep = 1;
      });
      return;
    }
    if (_wizStep == 1) {
      final reason = reasons.from2;
      if (reason != null) {
        setState(() {
          _inlineSaveError = reason;
          _supplierFieldError = null;
          _brokerFieldError = null;
        });
        return;
      }
      _autoSelectCommissionUnitFromLinesIfNeeded();
      setState(() => _wizStep = 2);
    }
  }

  Widget _wizBody(BuildContext context, List<Map<String, dynamic>> catalog, bool isEdit) {
    Widget step;
    switch (_wizStep) {
      case 0:
        step = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PurchasePartyStep(
            isEdit: isEdit,
            loadedDerivedStatus: _loadedDerivedStatus,
            loadedRemaining: _loadedRemaining,
            previewHumanId: _previewHumanId,
            editHumanId: _editHumanId,
            supplierCtrl: _supplierCtrl,
            brokerCtrl: _brokerCtrl,
            supplierFocusNode: _partySupplierFocus,
            brokerFocusNode: _partyBrokerFocus,
            onProceedFromParty: _partyAdvanceIfValid,
            supplierFieldError: _supplierFieldError,
            brokerFieldError: _brokerFieldError,
            catalog: catalog,
            lastGoodSuppliers: _lastGoodSuppliers,
            lastGoodBrokers: _lastGoodBrokers,
            lastAutoSupplierFromCatalogSig: _lastAutoSupplierFromCatalogSig,
            onLastAutoSupplierFromCatalogSigChanged: (sig) {
              setState(() => _lastAutoSupplierFromCatalogSig = sig);
            },
            onDraftChanged: _onDraftChanged,
            supplierSubtitleFor: _supplierSearchSubtitle,
            supplierRowId: _supplierRowId,
            supplierMapLabel: _supplierMapLabel,
            sortSuppliers: _sortSuppliersByPurchaseRecency,
            filterSuppliersByCatalog: _filterSuppliersByCatalogLineDefaults,
            onCatalogAutoSupplierSelected: _applySupplierSelection,
            onSupplierSelectedSync: _onUserSupplierSelected,
            openQuickSupplierCreate: _openQuickSupplierCreate,
            partyUserSupplierActionGen: () => _partyUserSupplierActionGeneration,
            onSupplierClear: () {
              setState(() {
                _partyUserSupplierActionGeneration++;
                _supplierFieldError = null;
                _brokerFieldError = null;
              });
              ref.read(purchaseDraftProvider.notifier).clearSupplier();
              _supplierCtrl.clear();
              _syncControllersFromDraft();
              _onDraftChanged();
            },
            applyBrokerSelection: _applyBrokerSelection,
            openQuickBrokerCreate: _openQuickBrokerCreate,
            brokerRowId: _brokerRowId,
            brokerMapLabel: _brokerMapLabel,
            supplierLastPurchaseById: _supplierLastPurchaseById,
            supplierBalanceById: _supplierBalanceById,
          ),
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Terms & charges',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
            ),
            const SizedBox(height: 12),
            PurchaseTermsOnlyStep(
              paymentDaysFocus: _termsPaymentDaysFocus,
              paymentDaysCtrl: _paymentDaysCtrl,
              commissionCtrl: _commissionCtrl,
              headerDiscCtrl: _headerDiscCtrl,
              narrationCtrl: _invoiceCtrl,
              commissionFocus: _termsCommissionFocus,
              headerDiscFocus: _termsHeaderDiscFocus,
              narrationFocus: _termsNarrationFocus,
              onDraftChanged: _onDraftChanged,
            ),
          ],
        );
        break;
      case 1:
        step = PurchaseFastItemsStep(
          listScrollController: _itemsStepListScrollController,
          onDraftChanged: _onDraftChanged,
          lineJustAdded: _lineJustAdded,
          onDismissLineJustAdded: () => setState(() => _lineJustAdded = null),
          openAdvancedItemEditor: ({editIndex, initialOverride}) =>
              _openItemSheet(
                catalog,
                editIndex: editIndex,
                initialOverride: initialOverride,
              ),
        );
        break;
      case 2:
        step = PurchaseReviewTallyStep(
          isEdit: isEdit,
          previewHumanId: _previewHumanId,
          editHumanId: _editHumanId,
        );
        break;
      default:
        step = const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Default AnimatedSwitcher centers children in free height — party fields
      // must stay at the top so keyboard + suggestion overlay have room below.
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: RepaintBoundary(
        child: Padding(
          key: ValueKey<int>(_wizStep),
          padding: EdgeInsets.zero,
          child: step,
        ),
      ),
    );
  }

  Widget _wizardFooterChrome(
    List<Map<String, dynamic>> catalog,
    bool isEdit, {
    required double kbInset,
  }) {
    // [Bug 3 fix] Continue is ALWAYS enabled. Clicking validates the step and
    // shows the exact missing field via [_wizNext]. No silent disables.
    final saveVal = ref.watch(purchaseSaveValidationProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_inlineSaveError != null)
          Material(
            color: Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _inlineSaveError!,
                style: TextStyle(color: Colors.red[900], fontSize: 12),
              ),
            ),
          ),
        if (_wizStep == 0 || _wizStep == 1) ...[
          SizedBox(
            height: kbInset > 0 ? 44 : 52,
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _wizNext,
              child: Text(
                _wizStep == 1 ? 'Review purchase →' : 'Continue →',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
        if (_wizStep == 2) ...[
          if (!saveVal.isOk)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                saveVal.errorMessage ??
                    (saveVal.lineErrors.isNotEmpty
                        ? saveVal.lineErrors.values.first
                        : ''),
                style: TextStyle(color: Colors.red[800], fontSize: 11),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: kbInset > 0 ? 44 : 52,
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _validateAndSave(shareAfterSave: false),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save Only',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: kbInset > 0 ? 44 : 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: HexaColors.brandAccent,
                    ),
                    onPressed: _isSaving
                        ? null
                        : () => _validateAndSave(shareAfterSave: true),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save & Share',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildWizardBody(
    BuildContext context,
    Widget stepContent,
    bool isEdit,
    List<Map<String, dynamic>> catalog,
    int wizStep,
  ) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: false,
      child: LayoutBuilder(
        builder: (ctx, _) {
          final kbInset = MediaQuery.viewInsetsOf(ctx).bottom;
            final stepScroll = wizStep == 2
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: stepContent,
                )
              : wizStep == 1
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: stepContent,
                    )
                  : SingleChildScrollView(
                  controller: _wizardBodyScrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, kbInset > 0 ? 250 : 100),
                  child: stepContent,
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: stepScroll),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      8,
                      12,
                      8 + (kbInset > 0
                          ? (kbInset - MediaQuery.paddingOf(ctx).bottom)
                              .clamp(0.0, 500.0)
                          : 0),
                    ),
                    child: _wizardFooterChrome(
                      catalog,
                      isEdit,
                      kbInset: kbInset,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tradePurchasePreviewProvider);
    ref.listen(catalogItemsListProvider, (_, next) {
      next.whenData((d) {
        _lastCatalogSnapshot = d
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
      });
    });
    ref.listen<(String?, String?)>(
      purchaseDraftProvider.select((d) => (d.supplierId, d.supplierName)),
      (prev, next) {
        if (!mounted) return;
        final hadSupplier =
            prev?.$1 != null && prev!.$1!.trim().isNotEmpty;
        final (nextId, nextName) = next;
        final hasSupplier =
            nextId != null && nextId.trim().isNotEmpty;
        if (!hasSupplier) {
          // Do not wipe the field whenever draft is (null,null) — that happens
          // on every unrelated draft edit before a supplier is picked; only clear
          // when we lose a supplier that was already committed.
          if (hadSupplier && _supplierCtrl.text.isNotEmpty) {
            _supplierCtrl.clear();
          }
          return;
        }
        final display = nextName?.trim() ?? '';
        if (display.isNotEmpty && _supplierCtrl.text != display) {
          _supplierCtrl.text = display;
        }
      },
    );
    ref.listen<(String?, String?)>(
      purchaseDraftProvider.select((d) => (d.brokerId, d.brokerName)),
      (prev, next) {
        if (!mounted) return;
        final hadBroker = prev?.$1 != null && prev!.$1!.trim().isNotEmpty;
        final (nextId, nextName) = next;
        final hasBroker = nextId != null && nextId.trim().isNotEmpty;
        if (!hasBroker) {
          if (hadBroker && _brokerCtrl.text.isNotEmpty) {
            _brokerCtrl.clear();
          }
          return;
        }
        final display = nextName?.trim() ?? '';
        if (display.isNotEmpty && _brokerCtrl.text != display) {
          _brokerCtrl.text = display;
        }
      },
    );
    ref.listen(suppliersListProvider, (prev, next) {
      next.whenData((d) => _lastGoodSuppliers = d);
    });
    ref.listen(brokersListProvider, (prev, next) {
      next.whenData((d) => _lastGoodBrokers = d);
    });
    ref.listen(
      purchaseDraftProvider.select((d) => d.supplierId),
      (prev, next) {
        if (next == null || next.isEmpty) {
          _lastAutoSupplierFromCatalogSig = null;
        }
      },
    );
    final isEdit = _isEditMode();
    final catalogAsync = ref.watch(catalogItemsListProvider);
    final catalog = catalogAsync.valueOrNull ??
        _lastCatalogSnapshot ??
        const <Map<String, dynamic>>[];

    final aiTok = widget.aiScanToken?.trim();
    final fromAiBill = !isEdit &&
        aiTok != null &&
        aiTok.isNotEmpty &&
        widget.aiScanBaseJson != null;

    final appBarTitle =
        fromAiBill
            ? switch (_wizStep) {
              0 => 'AI bill draft — Party & terms',
              1 => 'AI bill draft — Match items',
              _ => 'AI bill draft — Review & save',
            }
            : !isEdit
            ? switch (_wizStep) {
              0 => 'New purchase — Party & terms',
              1 => 'New purchase — Items',
              _ => 'New purchase — Review',
            }
            : switch (_wizStep) {
              0 => 'Edit purchase — Party & terms',
              1 => 'Edit purchase — Items',
              _ => 'Edit purchase — Review',
            };

    Widget purchaseWizardMainContent() {
      return Builder(
        builder: (bodyContext) {
          if (_isBootstrapping) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_editBootstrapError != null) {
            final err = _editBootstrapError!;
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 48, color: Colors.orange.shade800),
                    const SizedBox(height: 16),
                    Text(
                      err,
                      textAlign: TextAlign.center,
                      style: Theme.of(bodyContext).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: () => _bootstrap(),
                          child: const Text('Retry'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => bodyContext.pop(),
                          child: const Text('Go back'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          final emptyCache = catalog.isEmpty;
          final showTopLoad = catalogAsync.isLoading && emptyCache;
          final showCatalogErrorStrip =
              catalogAsync.hasError && emptyCache;

          final step = _wizBody(bodyContext, catalog, isEdit);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTopLoad)
                const SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (showCatalogErrorStrip)
                Material(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Catalog could not refresh. Check your connection and try again.',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _buildWizardBody(
                  bodyContext,
                  step,
                  isEdit,
                  catalog,
                  _wizStep,
                ),
              ),
            ],
          );
        },
      );
    }

    return PopScope(
      canPop: isEdit || !_formDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_wizStep > 0) {
          FocusScope.of(context).unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _wizStep -= 1);
          });
          return;
        }
        await _handleWizardExitFromRoot();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(appBarTitle),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isSaving ? null : () => _wizBack(),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: purchaseWizardMainContent(),
        ),
      ),
    );
  }
}
