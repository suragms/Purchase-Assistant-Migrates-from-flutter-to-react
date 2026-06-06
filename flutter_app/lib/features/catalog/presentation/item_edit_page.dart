import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/dashboard_role.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/item_detail_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'widgets/catalog_item_defaults_edit_form.dart';

class ItemEditPage extends ConsumerStatefulWidget {
  const ItemEditPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends ConsumerState<ItemEditPage> {
  final _formKey = GlobalKey<CatalogItemDefaultsEditFormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _hsnCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _kgCtrl;
  late final TextEditingController _ipbCtrl;
  late final TextEditingController _wptCtrl;
  late final TextEditingController _landCtrl;
  late final TextEditingController _sellCtrl;
  bool _saving = false;
  bool _controllersBound = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
    _hsnCtrl = TextEditingController();
    _taxCtrl = TextEditingController();
    _kgCtrl = TextEditingController();
    _ipbCtrl = TextEditingController();
    _wptCtrl = TextEditingController();
    _landCtrl = TextEditingController();
    _sellCtrl = TextEditingController();
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (_nameError != null && _nameCtrl.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _hsnCtrl.dispose();
    _taxCtrl.dispose();
    _kgCtrl.dispose();
    _ipbCtrl.dispose();
    _wptCtrl.dispose();
    _landCtrl.dispose();
    _sellCtrl.dispose();
    super.dispose();
  }

  void _bindControllers(Map<String, dynamic> item) {
    if (_controllersBound) return;
    _controllersBound = true;
    _nameCtrl.text = item['name']?.toString() ?? '';
    _codeCtrl.text = item['item_code']?.toString() ?? '';
    _hsnCtrl.text = item['hsn_code']?.toString() ?? '';
    _taxCtrl.text =
        item['tax_percent'] != null ? item['tax_percent'].toString() : '';
    _kgCtrl.text = item['default_kg_per_bag'] != null
        ? item['default_kg_per_bag'].toString()
        : '';
    _ipbCtrl.text = item['default_items_per_box'] != null
        ? item['default_items_per_box'].toString()
        : '';
    _wptCtrl.text = item['default_weight_per_tin'] != null
        ? item['default_weight_per_tin'].toString()
        : '';
    _landCtrl.text = item['default_landing_cost'] != null
        ? item['default_landing_cost'].toString()
        : '';
    _sellCtrl.text = item['default_selling_cost'] != null
        ? item['default_selling_cost'].toString()
        : '';
  }

  String? _openingStockLabel(Map<String, dynamic>? stock) {
    if (stock == null || stock.isEmpty) return null;
    final unitRaw = (stock['stock_unit'] ?? stock['unit'] ?? 'piece').toString();
    final unit = unitRaw.trim().isEmpty ? 'piece' : unitRaw.trim();
    final unitLabel = unit.toUpperCase();
    final qty = coerceToDouble(stock['opening_stock_qty']);
    final setAtRaw = stock['opening_stock_set_at']?.toString();
    final setAt = setAtRaw != null ? DateTime.tryParse(setAtRaw)?.toLocal() : null;
    final setBy = stock['opening_stock_set_by']?.toString().trim();

    if (setAt == null && qty <= 0.001) {
      return 'Not set yet';
    }
    final qtyText = '${formatStockQtyNumber(qty)} $unitLabel';
    if (setAt == null) return qtyText;
    final ago = _timeAgo(setAt);
    if (setBy != null && setBy.isNotEmpty) {
      return '$qtyText · set $ago by $setBy';
    }
    return '$qtyText · set $ago';
  }

  static String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'Item name is required');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      final ok = await saveCatalogItemDefaults(
        ref: ref,
        itemId: widget.itemId,
        unit: form.selectedUnit,
        nameCtrl: _nameCtrl,
        codeCtrl: _codeCtrl,
        hsnCtrl: _hsnCtrl,
        taxCtrl: _taxCtrl,
        kgCtrl: _kgCtrl,
        ipbCtrl: _ipbCtrl,
        wptCtrl: _wptCtrl,
        landCtrl: _landCtrl,
        sellCtrl: _sellCtrl,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item updated')),
        );
        context.popOrGo('/catalog/item/${widget.itemId}');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.error is String ? e.error as String : friendlyApiError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showOpeningStockSheet(double current) {
    showHexaBottomSheet<void>(
      context: context,
      compact: true,
      child: _EditOpeningStockSheet(
        itemId: widget.itemId,
        currentStock: current,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));
    final stock = ref.watch(itemDetailStockProvider(widget.itemId)).valueOrNull;
    final session = ref.watch(sessionProvider);
    final isOwner = session != null && sessionHasOwnerDashboard(session);
    final openingQty = coerceToDouble(stock?['opening_stock_qty']);
    final cachedItem = itemAsync.valueOrNull;
    final showFormSpinner = itemAsync.isLoading && cachedItem == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit item'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: showFormSpinner
          ? const Center(child: CircularProgressIndicator())
          : itemAsync.when(
        loading: () {
          final item = cachedItem;
          if (item == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _bindControllers(item);
          return _editForm(
            item: item,
            stock: stock,
            isOwner: isOwner,
            openingQty: openingQty,
            refreshing: true,
          );
        },
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load catalog item',
          onRetry: () =>
              ref.invalidate(catalogItemDetailProvider(widget.itemId)),
        ),
        data: (item) {
          _bindControllers(item);
          return _editForm(
            item: item,
            stock: stock,
            isOwner: isOwner,
            openingQty: openingQty,
            refreshing: itemAsync.isLoading && cachedItem != null,
          );
        },
      ),
    );
  }

  Widget _editForm({
    required Map<String, dynamic> item,
    required Map<String, dynamic>? stock,
    required bool isOwner,
    required double openingQty,
    bool refreshing = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refreshing)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: CatalogItemDefaultsEditForm(
            key: _formKey,
            pickerContext: context,
            nameError: _nameError,
            nameCtrl: _nameCtrl,
            codeCtrl: _codeCtrl,
            hsnCtrl: _hsnCtrl,
            taxCtrl: _taxCtrl,
            kgCtrl: _kgCtrl,
            ipbCtrl: _ipbCtrl,
            wptCtrl: _wptCtrl,
            landCtrl: _landCtrl,
            sellCtrl: _sellCtrl,
            initialUnit: item['default_unit']?.toString(),
            showHeader: true,
            openingStockLabel: _openingStockLabel(stock),
            canSetOpeningStock: isOwner,
            onSetOpeningStock: isOwner
                ? () => _showOpeningStockSheet(openingQty)
                : null,
          ),
        ),
      ],
    );
  }
}

class _EditOpeningStockSheet extends ConsumerStatefulWidget {
  const _EditOpeningStockSheet({
    required this.itemId,
    required this.currentStock,
  });

  final String itemId;
  final double currentStock;

  @override
  ConsumerState<_EditOpeningStockSheet> createState() =>
      _EditOpeningStockSheetState();
}

class _EditOpeningStockSheetState extends ConsumerState<_EditOpeningStockSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentStock > 0) {
      _ctrl.text = widget.currentStock.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final val = double.tryParse(_ctrl.text.trim());
    if (val == null || val < 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).setOpeningStock(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            qty: val,
          );
      ref.invalidate(itemDetailBundleProvider(widget.itemId));
      ref.invalidate(catalogItemDetailProvider(widget.itemId));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set opening stock',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening quantity',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('SET OPENING STOCK'),
          ),
        ],
      ),
    );
  }
}
