import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../shared/widgets/inline_search_field.dart';
import '../../purchase/presentation/widgets/party_inline_suggest_field.dart';

Future<bool> showStockQuickPurchaseSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _StockQuickPurchaseBody(item: item),
  );
  return result == true;
}

class _StockQuickPurchaseBody extends ConsumerStatefulWidget {
  const _StockQuickPurchaseBody({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_StockQuickPurchaseBody> createState() =>
      _StockQuickPurchaseBodyState();
}

class _StockQuickPurchaseBodyState
    extends ConsumerState<_StockQuickPurchaseBody> {
  final _qtyCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _qtyFocus = FocusNode();
  final _supplierFocus = FocusNode();
  final _brokerFocus = FocusNode();
  final _notesFocus = FocusNode();
  bool _saving = false;
  bool _intelLoaded = false;
  InlineSearchItem? _supplier;
  InlineSearchItem? _broker;
  late final String _idempotencyKey;

  String get _itemId => widget.item['id']?.toString() ?? '';
  String get _name => widget.item['name']?.toString() ?? 'Item';
  String get _unit =>
      widget.item['stock_unit']?.toString() ??
      widget.item['unit']?.toString() ??
      'piece';

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'quick-purchase:$_itemId:${DateTime.now().microsecondsSinceEpoch}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSmartDefaults());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _notesCtrl.dispose();
    _qtyFocus.dispose();
    _supplierFocus.dispose();
    _brokerFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  InlineSearchItem _partyItem(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? 'Unknown';
    final phone = row['phone']?.toString();
    final location = row['location']?.toString() ?? row['address']?.toString();
    return InlineSearchItem(
      id: id,
      label: name,
      subtitle: [
        if (phone != null && phone.trim().isNotEmpty) phone.trim(),
        if (location != null && location.trim().isNotEmpty) location.trim(),
      ].join(' • '),
      searchText: '$name ${phone ?? ''} ${location ?? ''}',
    );
  }

  bool _selectionMatches(
      InlineSearchItem? selected, TextEditingController ctrl) {
    if (selected == null) return false;
    return ctrl.text.trim().toLowerCase() ==
        selected.label.trim().toLowerCase();
  }

  Future<void> _loadSmartDefaults() async {
    final session = ref.read(sessionProvider);
    if (session == null || _itemId.isEmpty) return;
    try {
      final intel = await ref.read(hexaApiProvider).getItemPurchaseIntelligence(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted) return;
      final suggested = intel['suggested_qty'];
      if (_qtyCtrl.text.trim().isEmpty && suggested is num && suggested > 0) {
        _qtyCtrl.text = suggested.toStringAsFixed(0);
      }
      setState(() => _intelLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _intelLoaded = true);
    }
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    final parsed = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid purchase quantity')),
      );
      return;
    }
    if (!_selectionMatches(_supplier, _supplierCtrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a supplier from suggestions')),
      );
      return;
    }
    if (_brokerCtrl.text.trim().isNotEmpty &&
        !_selectionMatches(_broker, _brokerCtrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select broker from suggestions or clear it')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).createStockQuickPurchase(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
            qty: parsed,
            supplierId: _supplier!.id,
            brokerId: _brokerCtrl.text.trim().isEmpty ? null : _broker?.id,
            notes: _notesCtrl.text,
            idempotencyKey: _idempotencyKey,
          );
      invalidateWarehouseSurfaces(ref);
      ref.invalidate(stockListProvider);
      ref.invalidate(stockStatusCountsProvider);
      ref.invalidate(stockChangesFeedProvider);
      ref.invalidate(stockAuditPeriodProvider);
      ref.invalidate(homeInventorySummaryProvider);
      ref.invalidate(staffTodayActivityProvider);
      ref.invalidate(staffTodayStockWorkProvider);
      ref.invalidate(staffTodaySummaryProvider);
      if (_itemId.isNotEmpty) {
        ref.invalidate(stockItemIntelligenceProvider(_itemId));
        ref.invalidate(stockItemActivityProvider(_itemId));
      }
      ref.read(businessDataWriteRevisionProvider.notifier).state++;
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final current = coerceToDouble(widget.item['current_stock']);
    final suppliers = ref.watch(suppliersListProvider);
    final brokers = ref.watch(brokersListProvider);
    final supplierItems = suppliers.valueOrNull?.map(_partyItem).toList() ??
        const <InlineSearchItem>[];
    final brokerItems = brokers.valueOrNull?.map(_partyItem).toList() ??
        const <InlineSearchItem>[];
    final unitLabel = _unit.toUpperCase();

    return HexaResponsiveSheetViewport(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          Text(
            'Stock: ${stockDisplayPrimary(current, _unit)}',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Divider(height: 16),
          Text(
            'Purchase quantity',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _qtyCtrl,
            focusNode: _qtyFocus,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            onSubmitted: (_) => _supplierFocus.requestFocus(),
            decoration: InputDecoration(
              hintText: 'e.g. 100',
              isDense: true,
              suffixText: unitLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Supplier',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          PartyInlineSuggestField(
            controller: _supplierCtrl,
            focusNode: _supplierFocus,
            hintText: suppliers.isLoading
                ? 'Loading suppliers...'
                : 'Search supplier…',
            prefixIcon: const Icon(Icons.store_outlined, size: 18),
            minQueryLength: 0,
            maxMatches: 8,
            dense: true,
            suggestionsAsOverlay: true,
            textInputAction: TextInputAction.next,
            focusAfterSelection: _brokerFocus,
            items: supplierItems,
            onSelected: (it) {
              setState(() => _supplier = it);
            },
          ),
          const SizedBox(height: 14),
          if (!_intelLoaded)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Text(
            'Broker (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          PartyInlineSuggestField(
            controller: _brokerCtrl,
            focusNode: _brokerFocus,
            hintText:
                brokers.isLoading ? 'Loading brokers...' : 'Search broker…',
            prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
            minQueryLength: 0,
            maxMatches: 8,
            dense: true,
            suggestionsAsOverlay: true,
            textInputAction: TextInputAction.next,
            focusAfterSelection: _notesFocus,
            items: brokerItems,
            onSelected: (it) {
              setState(() => _broker = it);
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Notes (optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            focusNode: _notesFocus,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'Optional notes...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('ADD PURCHASE', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          ],
        ),
      ),
      ),
    );
  }
}

