import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart' show stockChangesFeedProvider;
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
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
    backgroundColor: HexaColors.brandCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: _StockQuickPurchaseBody(item: item),
    ),
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
      invalidateWarehouseSurfaces(ref, itemId: _itemId);
      ref.invalidate(stockChangesFeedProvider);
      ref.invalidate(staffTodayActivityProvider);
      ref.invalidate(staffTodayStockWorkProvider);
      ref.invalidate(staffTodaySummaryProvider);
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

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? prefixIcon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: HexaColors.brandBackground,
      prefixIcon: prefixIcon,
      suffixText: suffixText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandAccent, width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: HexaDsType.label(12).copyWith(
          fontWeight: FontWeight.w700,
          color: HexaColors.textBody,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = coerceToDouble(widget.item['current_stock']);
    final suppliers = ref.watch(suppliersListProvider);
    final brokers = ref.watch(brokersListProvider);
    final supplierItems = suppliers.valueOrNull?.map(_partyItem).toList() ??
        const <InlineSearchItem>[];
    final brokerItems = brokers.valueOrNull?.map(_partyItem).toList() ??
        const <InlineSearchItem>[];
    final unitLabel = _unit.toUpperCase();
    final stockLabel = stockDisplayPrimary(current, _unit);

    return HexaResponsiveSheetViewport(
      compact: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick purchase',
                        style: HexaDsType.label(11).copyWith(
                          fontWeight: FontWeight.w800,
                          color: HexaColors.brandAccent,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.h3(context).copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: HexaColors.brandPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: HexaColors.brandPrimary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: HexaColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current stock · $stockLabel',
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_intelLoaded) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 12),
            _fieldLabel('Purchase quantity'),
            TextField(
              controller: _qtyCtrl,
              focusNode: _qtyFocus,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onSubmitted: (_) => _supplierFocus.requestFocus(),
              decoration: _fieldDecoration(
                hint: 'e.g. 100',
                suffixText: unitLabel,
              ),
            ),
            const SizedBox(height: 10),
            _fieldLabel('Supplier'),
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
            const SizedBox(height: 10),
            _fieldLabel('Broker (optional)'),
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
            const SizedBox(height: 10),
            _fieldLabel('Notes (optional)'),
            TextField(
              controller: _notesCtrl,
              focusNode: _notesFocus,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: _fieldDecoration(hint: 'Optional notes…'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: HexaColors.brandPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Add purchase',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
