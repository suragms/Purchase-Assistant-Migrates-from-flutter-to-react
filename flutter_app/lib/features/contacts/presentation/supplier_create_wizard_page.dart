import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/widgets/form_feedback.dart';
import '../../../core/widgets/async_value_form.dart';
import '../../catalog/catalog_taxonomy_utils.dart';
import '../../../shared/widgets/keyboard_safe_form_viewport.dart';

const _kDraftKey = 'supplier_create_wizard_draft_v1';

const _stepTitles = <String>[
  'Basic details',
  'Business details',
  'Brokers',
  'Items & categories',
  'Review',
];

int _levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var v0 = List<int>.generate(n + 1, (j) => j);
  var v1 = List<int>.filled(n + 1, 0);
  for (var i = 0; i < m; i++) {
    v1[0] = i + 1;
    for (var j = 0; j < n; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final ins = v1[j] + 1;
      final del = v0[j + 1] + 1;
      final sub = v0[j] + cost;
      v1[j + 1] = ins < del ? (ins < sub ? ins : sub) : (del < sub ? del : sub);
    }
    final t = v0;
    v0 = v1;
    v1 = t;
  }
  return v0[n];
}

double _nameSimilarity(String a, String b) {
  final A = a.toLowerCase().trim();
  final B = b.toLowerCase().trim();
  if (A.isEmpty || B.isEmpty) return 0;
  if (A == B) return 1;
  final d = _levenshtein(A, B);
  final maxL = A.length > B.length ? A.length : B.length;
  return 1 - d / maxL;
}

bool _validPhoneDigits(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  return d.length >= 10 && d.length <= 15;
}

class SupplierCreateWizardPage extends ConsumerStatefulWidget {
  const SupplierCreateWizardPage({super.key, this.supplierId});

  final String? supplierId;

  @override
  ConsumerState<SupplierCreateWizardPage> createState() =>
      _SupplierCreateWizardPageState();
}

class _SupplierCreateWizardPageState
    extends ConsumerState<SupplierCreateWizardPage> {
  int _step = 0;
  bool _dirty = false;
  bool _savedOnce = false;
  String? _fuzzyOkForName;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _loc = TextEditingController();
  final _gst = TextEditingController();
  final _addr = TextEditingController();
  final _notes = TextEditingController();
  final _itemSearch = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _locFocus = FocusNode();
  final _gstFocus = FocusNode();
  final _addrFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _itemSearchFocus = FocusNode();

  String? _nameError;
  String? _phoneError;
  String? _gstError;

  bool _aiMemory = false;

  final Set<String> _brokerIds = {};
  final Set<String> _categoryIds = {};
  final Set<String> _typeIds = {};
  final Set<String> _itemIds = {};
  final Map<String, String> _itemLabels = {};

  List<Map<String, dynamic>> _supplierRows = [];
  Timer? _dupTimer;
  String? _dupHint;

  Timer? _itemSearchDebounce;
  List<Map<String, dynamic>> _itemHits = [];

  @override
  void initState() {
    super.initState();
    _name.addListener(_scheduleDupCheck);
    for (final n in <FocusNode>[
      _nameFocus,
      _phoneFocus,
      _locFocus,
      _gstFocus,
      _addrFocus,
      _notesFocus,
      _itemSearchFocus,
    ]) {
      n.addListener(() {
        if (n.hasFocus) _scrollFocusedFieldIntoView(n);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
      _nameFocus.requestFocus();
    });
  }

  /// Scrolls the focused field into view after the keyboard begins animating.
  void _scrollFocusedFieldIntoView(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 85));
      if (!mounted || !node.hasFocus) return;
      final ctx = node.context;
      if (ctx == null || !ctx.mounted) return;
      final ro = ctx.findRenderObject();
      if (ro == null || !ro.attached) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  EdgeInsets _fieldScrollPad(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return EdgeInsets.only(bottom: 24 + kb);
  }

  void _unfocusForm() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _focusFirstFieldForStep(int step) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (step) {
        case 1:
          _gstFocus.requestFocus();
          break;
        case 3:
          _itemSearchFocus.requestFocus();
          break;
        default:
          break;
      }
    });
  }

  /// Migrate draft step indices from the older 6-step wizard (purchase defaults removed).
  int _mapLegacyDraftStep(int oldStep) {
    final o = oldStep.clamp(0, 5);
    if (o <= 1) return o;
    if (o == 2) return 2;
    return o - 1;
  }

  Future<void> _bootstrap() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final rows = await ref.read(hexaApiProvider).listSuppliers(
            businessId: session.primaryBusiness.id,
          );
      if (mounted) {
        setState(() {
          _supplierRows = rows;
        });
      }
    } catch (_) {}
    if (widget.supplierId != null && widget.supplierId!.isNotEmpty) {
      try {
        final s = await ref.read(hexaApiProvider).getSupplier(
              businessId: session.primaryBusiness.id,
              supplierId: widget.supplierId!,
            );
        if (mounted && s.isNotEmpty) {
          setState(() {
            _name.text = s['name']?.toString() ?? '';
            _phone.text = s['phone']?.toString() ?? '';
            _loc.text = s['location']?.toString() ?? '';
            _gst.text = s['gst_number']?.toString() ?? '';
            _addr.text = s['address']?.toString() ?? '';
            _notes.text = s['notes']?.toString() ?? '';
            _aiMemory = s['ai_memory_enabled'] == true;
            _brokerIds
              ..clear()
              ..addAll(
                ((s['broker_ids'] as List?) ?? const [])
                    .map((e) => e.toString())
                    .where((e) => e.isNotEmpty),
              );
            try {
              final raw = s['preferences_json']?.toString();
              if (raw != null && raw.trim().isNotEmpty) {
                final p = jsonDecode(raw) as Map<String, dynamic>;
                _categoryIds
                  ..clear()
                  ..addAll((p['category_ids'] as List? ?? const [])
                      .map((e) => e.toString()));
                _typeIds
                  ..clear()
                  ..addAll((p['type_ids'] as List? ?? const [])
                      .map((e) => e.toString()));
                _itemIds
                  ..clear()
                  ..addAll((p['item_ids'] as List? ?? const [])
                      .map((e) => e.toString()));
              }
            } catch (_) {}
            _dirty = false;
          });
        }
      } catch (_) {}
    }
    if (widget.supplierId == null || widget.supplierId!.isEmpty) {
      await _loadDraft(session.primaryBusiness.id);
    }
  }

  void _scheduleDupCheck() {
    _dupTimer?.cancel();
    _dupTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final n = _name.text.trim();
      if (n.length < 2) {
        setState(() => _dupHint = null);
        return;
      }
      String? best;
      var bestScore = 0.0;
      for (final r in _supplierRows) {
        final ex = r['name']?.toString() ?? '';
        if (ex.isEmpty) continue;
        final s = _nameSimilarity(n, ex);
        if (s > bestScore && s < 1) {
          bestScore = s;
          best = ex;
        }
      }
      setState(() {
        _dupHint = bestScore >= 0.72 && best != null
            ? 'Similar supplier: "$best" — check before saving.'
            : null;
      });
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _loadDraft(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kDraftKey|$businessId');
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        final rawStep = ((m['step'] as num?)?.toInt() ?? 0);
        _step = _mapLegacyDraftStep(rawStep).clamp(0, 4);
        _name.text = m['name']?.toString() ?? '';
        _phone.text = m['phone']?.toString() ?? '';
        _loc.text = m['location']?.toString() ?? '';
        _gst.text = m['gst']?.toString() ?? '';
        _addr.text = m['address']?.toString() ?? '';
        _notes.text = m['notes']?.toString() ?? '';
        _aiMemory = m['ai_memory'] == true;
        _brokerIds
          ..clear()
          ..addAll((m['brokers'] as List?)?.map((e) => e.toString()) ?? []);
        _categoryIds
          ..clear()
          ..addAll((m['cats'] as List?)?.map((e) => e.toString()) ?? []);
        _typeIds
          ..clear()
          ..addAll((m['types'] as List?)?.map((e) => e.toString()) ?? []);
        _itemIds
          ..clear()
          ..addAll((m['items'] as List?)?.map((e) => e.toString()) ?? []);
        if (m['item_labels'] is Map) {
          _itemLabels
            ..clear()
            ..addAll(Map<String, String>.from(
              (m['item_labels'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            ));
        }
        _dirty = false;
      });
    } catch (_) {}
  }

  Future<void> _persistDraft(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final m = <String, dynamic>{
      'step': _step,
      'name': _name.text,
      'phone': _phone.text,
      'location': _loc.text,
      'gst': _gst.text,
      'address': _addr.text,
      'notes': _notes.text,
      'ai_memory': _aiMemory,
      'brokers': _brokerIds.toList(),
      'cats': _categoryIds.toList(),
      'types': _typeIds.toList(),
      'items': _itemIds.toList(),
      'item_labels': _itemLabels,
    };
    await prefs.setString('$_kDraftKey|$businessId', jsonEncode(m));
  }

  Future<void> _clearDraft(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kDraftKey|$businessId');
  }

  Future<void> _handleExitRequest() async {
    if (_savedOnce) {
      if (mounted) context.pop();
      return;
    }
    if (!_dirty) {
      if (mounted) context.pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave supplier setup?'),
        content: const Text('Save a draft to continue later, or discard your changes.'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop('cancel'),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => ctx.pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => ctx.pop('draft'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel' || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    if (action == 'draft') {
      await _persistDraft(bid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved')),
        );
        context.pop();
      }
    } else {
      await _clearDraft(bid);
      if (mounted) context.pop();
    }
  }

  bool _validateStep0() {
    var ok = true;
    _nameError = null;
    _phoneError = null;
    if (_name.text.trim().isEmpty) {
      _nameError = 'Required';
      ok = false;
    }
    final rawPhone = _phone.text.trim();
    if (rawPhone.isNotEmpty && !_validPhoneDigits(_phone.text)) {
      _phoneError = 'Enter a valid phone (10–15 digits)';
      ok = false;
    }
    setState(() {});
    return ok;
  }

  /// Blocks create/rename when another supplier already uses this name (case-insensitive).
  String? _blockingDuplicateName(String candidate) {
    final c = candidate.trim().toLowerCase();
    if (c.isEmpty) return null;
    final self = widget.supplierId?.trim();
    for (final r in _supplierRows) {
      final id = r['id']?.toString();
      if (self != null && self.isNotEmpty && id == self) continue;
      final ex = (r['name']?.toString() ?? '').trim().toLowerCase();
      if (ex.isNotEmpty && ex == c) {
        return r['name']?.toString() ?? ex;
      }
    }
    return null;
  }

  Future<bool> _confirmFuzzyIfNeeded() async {
    final n = _name.text.trim();
    if (n.isEmpty) return true;
    if (_fuzzyOkForName == n) return true;
    var best = 0.0;
    String? label;
    for (final r in _supplierRows) {
      final ex = r['name']?.toString() ?? '';
      if (ex.isEmpty) continue;
      final s = _nameSimilarity(n, ex);
      if (s > best && s < 1) {
        best = s;
        label = ex;
      }
    }
    if (best < 0.78 || label == null) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Similar supplier exists'),
        content: Text(
          'You already have "$label". Continue creating "${_name.text.trim()}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go == true) {
      _fuzzyOkForName = n;
      return true;
    }
    return false;
  }

  Future<void> _saveSupplier() async {
    if (!_validateStep0()) {
      setState(() => _step = 0);
      return;
    }
    final gstT = _gst.text.trim();
    if (gstT.isNotEmpty) {
      final re = RegExp(
        r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
        caseSensitive: false,
      );
      if (!re.hasMatch(gstT.toUpperCase())) {
        if (!mounted) return;
        setState(() {
          _gstError = 'Invalid GST format (e.g. 32ABCDE1234F1Z5).';
          _step = 1;
        });
        return;
      }
    }
    final dupExact = _blockingDuplicateName(_name.text);
    if (dupExact != null) {
      if (!mounted) return;
      setState(() {
        _nameError = 'Supplier "$dupExact" already exists.';
        _step = 0;
      });
      return;
    }
    if (!await _confirmFuzzyIfNeeded()) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final prefsMap = <String, dynamic>{
      'category_ids': _categoryIds.toList(),
      'type_ids': _typeIds.toList(),
      'item_ids': _itemIds.toList(),
    };
    try {
      String? id;
      if (widget.supplierId != null && widget.supplierId!.isNotEmpty) {
        final updated = await ref.read(hexaApiProvider).updateSupplier(
              businessId: bid,
              supplierId: widget.supplierId!,
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              location: _loc.text.trim().isEmpty ? null : _loc.text.trim(),
              brokerIds: _brokerIds.toList(),
              brokerId: _brokerIds.isEmpty ? null : _brokerIds.first,
              gstNumber: _gst.text.trim().isEmpty ? null : _gst.text.trim(),
              address: _addr.text.trim().isEmpty ? null : _addr.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              aiMemoryEnabled: _aiMemory,
              preferences: prefsMap,
            );
        id = updated['id']?.toString() ?? widget.supplierId;
      } else {
        final created = await ref.read(hexaApiProvider).createSupplier(
              businessId: bid,
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              location: _loc.text.trim().isEmpty ? null : _loc.text.trim(),
              brokerIds: _brokerIds.isEmpty ? null : _brokerIds.toList(),
              gstNumber: _gst.text.trim().isEmpty ? null : _gst.text.trim(),
              address: _addr.text.trim().isEmpty ? null : _addr.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              aiMemoryEnabled: _aiMemory,
              preferences: prefsMap,
            );
        id = created['id']?.toString();
      }
      await _clearDraft(bid);
      if (!mounted) return;
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      invalidateTradePurchaseCaches(ref);
      invalidateBusinessAggregates(ref);
      setState(() {
        _dirty = false;
        _savedOnce = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              widget.supplierId != null ? 'Supplier updated' : 'Supplier saved'),
          action: SnackBarAction(
            label: 'New purchase',
            onPressed: () {
              ref.read(pendingPurchaseSupplierIdProvider.notifier).state = id;
              context.push('/purchase/new');
            },
          ),
        ),
      );
      if (widget.supplierId == null || widget.supplierId!.isEmpty) {
        context.pop({'supplier_id': id});
        if (id != null && id.isNotEmpty && context.mounted) {
          context.push('/supplier/$id');
        }
      } else {
        context.pop({'supplier_id': id});
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      if (code == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A supplier with this name already exists.'),
          ),
        );
        setState(() => _step = 0);
        return;
      }
      showRetryableErrorSnackBar(context, e, onRetry: () {
        if (context.mounted) unawaited(_saveSupplier());
      });
    } catch (e) {
      if (!mounted) return;
      showRetryableErrorSnackBar(context, e, onRetry: () {
        if (context.mounted) unawaited(_saveSupplier());
      });
    }
  }

  Future<void> _addBrokerInline() async {
    final name = TextEditingController();
    final comm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New broker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              scrollPadding: _fieldScrollPad(context),
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: comm,
              scrollPadding: _fieldScrollPad(context),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Commission % (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final b = await ref.read(hexaApiProvider).createBroker(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
            commissionValue: double.tryParse(comm.text.trim()),
          );
      final id = b['id']?.toString();
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      invalidateBusinessAggregates(ref);
      if (id != null && id.isNotEmpty) {
        setState(() {
          _brokerIds.add(id);
          _markDirty();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  void _runItemSearch(String q) {
    _itemSearchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _itemHits = []);
      return;
    }
    _itemSearchDebounce = Timer(const Duration(milliseconds: 380), () async {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      try {
        final res = await ref.read(hexaApiProvider).unifiedSearch(
              businessId: session.primaryBusiness.id,
              q: q.trim(),
            );
        final items = res['catalog_items'];
        final list = <Map<String, dynamic>>[];
        if (items is List) {
          for (final e in items.take(24)) {
            if (e is Map) list.add(Map<String, dynamic>.from(e));
          }
        }
        if (mounted) setState(() => _itemHits = list);
      } catch (_) {
        if (mounted) setState(() => _itemHits = []);
      }
    });
  }

  InputDecoration _dec(String label, {String? hint, String? error}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _stepHeader(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Supplier basics'),
        if (_dupHint != null) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dupHint!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _name,
          focusNode: _nameFocus,
          scrollPadding: _fieldScrollPad(context),
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Supplier name *', error: _nameError),
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            _markDirty();
            if (_nameError != null) setState(() => _nameError = null);
          },
          onSubmitted: (_) => _phoneFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          focusNode: _phoneFocus,
          scrollPadding: _fieldScrollPad(context),
          keyboardType: TextInputType.phone,
          decoration: _dec('Phone *', error: _phoneError),
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            _markDirty();
            if (_phoneError != null) setState(() => _phoneError = null);
          },
          onSubmitted: (_) => _locFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loc,
          focusNode: _locFocus,
          scrollPadding: _fieldScrollPad(context),
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec('Location', hint: 'Optional'),
          textInputAction: TextInputAction.done,
          onChanged: (_) => _markDirty(),
          onSubmitted: (_) => _unfocusForm(),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('GST & notes'),
        TextField(
          controller: _gst,
          focusNode: _gstFocus,
          scrollPadding: _fieldScrollPad(context),
          textCapitalization: TextCapitalization.characters,
          decoration: _dec('GST number', hint: 'Important for invoices', error: _gstError),
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            _markDirty();
            if (_gstError != null) setState(() => _gstError = null);
          },
          onSubmitted: (_) => _addrFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addr,
          focusNode: _addrFocus,
          scrollPadding: _fieldScrollPad(context),
          maxLines: 2,
          decoration: _dec('Address', hint: 'Optional'),
          textInputAction: TextInputAction.next,
          onChanged: (_) => _markDirty(),
          onSubmitted: (_) => _notesFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          focusNode: _notesFocus,
          scrollPadding: _fieldScrollPad(context),
          maxLines: 3,
          decoration: _dec('Notes', hint: 'Optional'),
          textInputAction: TextInputAction.done,
          onChanged: (_) => _markDirty(),
          onSubmitted: (_) => _unfocusForm(),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final brokers = ref.watch(brokersListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Brokers on this supplier'),
        OutlinedButton.icon(
          onPressed: _addBrokerInline,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Create new broker'),
        ),
        const SizedBox(height: 12),
        brokers.whenForm(
          initialLoading: () => const LinearProgressIndicator(),
          reloadingBanner: (_) => formReloadBanner(),
          data: (rows) {
            if (rows.isEmpty) {
              return const Text('No brokers yet — create one above.');
            }
            return Column(
              children: rows.map((b) {
                final id = b['id']?.toString() ?? '';
                final name = b['name']?.toString() ?? '';
                final cv = b['commission_value'];
                final sub = cv != null ? 'Commission: $cv%' : 'Commission: —';
                final checked = _brokerIds.contains(id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _brokerIds.add(id);
                      } else {
                        _brokerIds.remove(id);
                      }
                      _markDirty();
                    });
                  },
                  title: Text(name),
                  subtitle: Text(sub),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStep4() {
    final cats = ref.watch(itemCategoriesListProvider);
    final recent = ref.watch(contactsItemsProvider);
    final recentByItem = <String, Map<String, dynamic>>{};
    for (final r in recent.valueOrNull ?? const <Map<String, dynamic>>[]) {
      final n = r['item_name']?.toString().trim().toLowerCase();
      if (n != null && n.isNotEmpty) {
        recentByItem[n] = r;
      }
    }
    // Must not use an unbounded ListView inside the outer SingleChildScrollView (Step 5 was blank in release).
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _stepHeader('Categories & items'),
        const Text('Preferred categories'),
        const SizedBox(height: 8),
        cats.whenForm(
          initialLoading: () => const LinearProgressIndicator(),
          reloadingBanner: (_) => formReloadBanner(),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load categories. Check your connection, then go back and open this step again.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Text(
                  'No categories in catalog yet. Add categories under Catalog, then return here.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rows.map((c) {
              final id = c['id']?.toString() ?? '';
              final name = c['name']?.toString() ?? '';
              final sel = _categoryIds.contains(id);
              return FilterChip(
                label: Text(name),
                selected: sel,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _categoryIds.add(id);
                    } else {
                      _categoryIds.remove(id);
                    }
                    _markDirty();
                  });
                },
              );
            }).toList(),
                ),
        ),
        if (_categoryIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Preferred subcategories (types)'),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final typesIndexAsync = ref.watch(categoryTypesIndexProvider);
              return typesIndexAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (index) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final cid in _categoryIds)
                      Builder(
                        builder: (context) {
                          final types = typesForCategory(index, cid);
                          if (types.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: types.map((t) {
                                final tid = t['id']?.toString() ?? '';
                                final name = t['name']?.toString() ?? '';
                                final sel = _typeIds.contains(tid);
                                return FilterChip(
                                  label: Text(name),
                                  selected: sel,
                                  onSelected: (v) {
                                    setState(() {
                                      if (v) {
                                        _typeIds.add(tid);
                                      } else {
                                        _typeIds.remove(tid);
                                      }
                                      _markDirty();
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        const Text('Frequently supplied items'),
        const SizedBox(height: 8),
        TextField(
          controller: _itemSearch,
          focusNode: _itemSearchFocus,
          scrollPadding: _fieldScrollPad(context),
          decoration: _dec('Search items or categories', hint: 'Type 2+ letters'),
          textInputAction: TextInputAction.next,
          onChanged: _runItemSearch,
          onSubmitted: (_) => _unfocusForm(),
        ),
        if (_itemHits.isNotEmpty)
          ..._itemHits.map((h) {
            final id = h['id']?.toString();
            final name =
                h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item';
            if (id == null || id.isEmpty) return const SizedBox.shrink();
            final picked = _itemIds.contains(id);
            final meta = recentByItem[name.toLowerCase()];
            final avg = (meta?['avg_landing'] as num?)?.toDouble();
            final supplierHint = meta?['supplier_name']?.toString();
            return ListTile(
              dense: true,
              title: Text(name),
              subtitle: Text(
                [
                  if ((h['category']?.toString() ?? '').isNotEmpty)
                    h['category']?.toString() ?? '',
                  if (avg != null) 'Last price: ${avg.toStringAsFixed(2)}',
                  if (supplierHint != null && supplierHint.isNotEmpty)
                    'Hint: from $supplierHint',
                ].join('  ·  '),
              ),
              trailing: picked
                  ? const Icon(Icons.check_circle_rounded, color: Colors.teal)
                  : const Icon(Icons.add_circle_outline_rounded),
              onTap: () {
                setState(() {
                  if (picked) {
                    _itemIds.remove(id);
                    _itemLabels.remove(id);
                  } else {
                    _itemIds.add(id);
                    _itemLabels[id] = name;
                  }
                  _markDirty();
                });
              },
            );
          }),
        recent.whenForm(
          initialLoading: () => const SizedBox.shrink(),
          data: (rows) {
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Recent from your purchases',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: rows.take(12).map((r) {
                    final n = r['item_name']?.toString() ?? '';
                    if (n.length < 2) return const SizedBox.shrink();
                    return ActionChip(
                      label: Text(n),
                      onPressed: () {
                        _itemSearch.text = n;
                        _runItemSearch(n);
                        _markDirty();
                      },
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
        if (_itemIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Selected (${_itemIds.length})',
              style: Theme.of(context).textTheme.titleSmall),
          ..._itemIds.map((id) {
            final label = _itemLabels[id] ?? id;
            return ListTile(
              dense: true,
              title: Text(label),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _itemIds.remove(id);
                    _itemLabels.remove(id);
                    _markDirty();
                  });
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildStep6() {
    final brokers = ref.watch(brokersListProvider).valueOrNull ?? const [];
    final brokerRows = brokers
        .where((b) => _brokerIds.contains(b['id']?.toString() ?? ''))
        .toList();
    final cats = ref.watch(itemCategoriesListProvider).valueOrNull ?? const [];
    final catNames = cats
        .where((c) => _categoryIds.contains(c['id']?.toString() ?? ''))
        .map((c) => c['name']?.toString() ?? '')
        .where((n) => n.trim().isNotEmpty)
        .toList();
    final itemNames = _itemIds
        .map((id) => _itemLabels[id])
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty)
        .toList();
    final notes = _notes.text.trim();
    final notesPreview =
        notes.length > 96 ? '${notes.substring(0, 96)}…' : notes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Review Supplier'),
        Text(
          'Final check before save',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        _reviewCard(
          title: 'Supplier Summary',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name.text.trim().isEmpty ? '—' : _name.text.trim(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (_loc.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _loc.text.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _miniFact('Phone',
                        _phone.text.trim().isEmpty ? '—' : _phone.text.trim()),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _miniFact(
                        'GST', _gst.text.trim().isEmpty ? '—' : _gst.text.trim()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _miniFact('Status', 'Active')),
                ],
              ),
            ],
          ),
        ),
        _reviewCard(
          title: 'Business Info',
          onEdit: () => setState(() => _step = 1),
          child: Column(
            children: [
              _kvRow('GST Number', _gst.text.trim().isEmpty ? '—' : _gst.text.trim()),
              _kvRow('Address', _addr.text.trim().isEmpty ? '—' : _addr.text.trim()),
              _kvRow('Notes', notesPreview.isEmpty ? '—' : notesPreview),
            ],
          ),
        ),
        _reviewCard(
          title: 'Brokers',
          onEdit: () => setState(() => _step = 2),
          child: brokerRows.isEmpty
              ? Text(
                  'No brokers linked',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              : Column(
                  children: brokerRows.map((b) {
                    final n = b['name']?.toString().trim();
                    final cv = b['commission_value']?.toString().trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              n == null || n.isEmpty ? 'Broker' : n,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            (cv == null || cv.isEmpty)
                                ? 'Commission: —'
                                : 'Commission: $cv%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        _reviewCard(
          title: 'Items & Categories',
          onEdit: () => setState(() => _step = 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kvRow('Categories',
                  catNames.isEmpty ? 'None linked yet' : '${catNames.length} linked'),
              _kvRow('Items',
                  itemNames.isEmpty ? 'None linked yet' : '${itemNames.length} linked'),
              if (itemNames.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Recent preview',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                ...itemNames.take(3).map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('• $n'),
                      ),
                    ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Link items on the Categories & items step.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),
        _reviewCard(
          title: 'Relation Flow',
          child: Text(
            '${_name.text.trim().isEmpty ? 'Supplier' : _name.text.trim()} \u2192 ${brokerRows.length} Broker${brokerRows.length == 1 ? '' : 's'} \u2192 ${itemNames.length} Item${itemNames.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }

  Widget _reviewCard({
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (onEdit != null)
                  TextButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
              ],
            ),
            children: [child],
          ),
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _miniFact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _bodyForStep() {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return _buildStep6();
    }
  }

  Widget _wizardBottomBar() {
    final isSummary = _step == 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
            if (isSummary) ...[
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saveSupplier,
                  child: const Text('Save'),
                ),
              ),
            ] else ...[
              Expanded(
                child: TextButton(
                  onPressed: _handleExitRequest,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (_step == 0 && !_validateStep0()) return;
                    final nextStep = (_step + 1).clamp(0, 4);
                    setState(() {
                      _step = nextStep;
                      _dirty = true;
                    });
                    _unfocusForm();
                    _focusFirstFieldForStep(nextStep);
                  },
                  child: const Text('Next'),
                ),
              ),
            ],
          ],
        ),
      );
  }

  @override
  void dispose() {
    _dupTimer?.cancel();
    _itemSearchDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _loc.dispose();
    _gst.dispose();
    _addr.dispose();
    _notes.dispose();
    _itemSearch.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _locFocus.dispose();
    _gstFocus.dispose();
    _addrFocus.dispose();
    _notesFocus.dispose();
    _itemSearchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.supplierId != null ? 'Edit supplier' : 'New supplier';
    final subtitle = '${_stepTitles[_step]} · Step ${_step + 1} of ${_stepTitles.length}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_step > 0) {
          setState(() => _step--);
          return;
        }
        await _handleExitRequest();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_step > 0) {
                setState(() => _step--);
              } else {
                unawaited(_handleExitRequest());
              }
            },
          ),
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, cts) {
                final minFields = math.max(220.0, cts.maxHeight - 280);
                return KeyboardSafeFormViewport(
                  dismissKeyboardOnTap: false,
                  horizontalPadding: 16,
                  topPadding: 16,
                  minFieldsHeight:
                      cts.hasBoundedHeight ? minFields : 220,
                  fields: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _bodyForStep(),
                    ],
                  ),
                  footer: Material(
                    elevation: 8,
                    surfaceTintColor: Colors.transparent,
                    color: Theme.of(context).colorScheme.surface,
                    child: _wizardBottomBar(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
