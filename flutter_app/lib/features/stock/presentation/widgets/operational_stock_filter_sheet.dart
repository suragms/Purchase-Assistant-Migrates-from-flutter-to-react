import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/providers/suppliers_list_provider.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../../../shared/widgets/search_picker_sheet.dart';
import 'stock_bulk_actions_sheet.dart';

const kOperationalDesktopBreakpoint = 1100.0;

/// Opens advanced filter UI (category, supplier, etc.) — not unit/status chips.
Future<void> showOperationalStockFilter({
  required BuildContext context,
  required WidgetRef ref,
  TextEditingController? subcategoryCtrl,
  bool includeSupplier = true,
  bool isStaffMode = false,
  double bottomNavInset = 0,
}) async {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= kOperationalDesktopBreakpoint) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 12,
            child: SizedBox(
              width: 320,
              height: MediaQuery.sizeOf(ctx).height,
              child: _OperationalFilterBody(
                subcategoryCtrl: subcategoryCtrl,
                includeSupplier: includeSupplier,
                isStaffMode: isStaffMode,
                bottomNavInset: bottomNavInset,
              ),
            ),
          ),
        );
      },
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => _OperationalFilterBody(
        subcategoryCtrl: subcategoryCtrl,
        includeSupplier: includeSupplier,
        isStaffMode: isStaffMode,
        scrollController: scrollCtrl,
        bottomNavInset: bottomNavInset,
      ),
    ),
  );
}

class _OperationalFilterBody extends ConsumerStatefulWidget {
  const _OperationalFilterBody({
    this.subcategoryCtrl,
    this.includeSupplier = true,
    this.isStaffMode = false,
    this.scrollController,
    this.bottomNavInset = 0,
  });

  final TextEditingController? subcategoryCtrl;
  final bool includeSupplier;
  final bool isStaffMode;
  final ScrollController? scrollController;
  final double bottomNavInset;

  @override
  ConsumerState<_OperationalFilterBody> createState() =>
      _OperationalFilterBodyState();
}

class _OperationalFilterBodyState
    extends ConsumerState<_OperationalFilterBody> {
  late String _sort;
  late String _category;
  late String _supplier;
  late bool _missingBarcode;
  late bool _missingItemCode;
  late bool _reorderOnly;
  late bool _purchasedInPeriodOnly;
  late String _unit;
  late final TextEditingController _subcatField;

  @override
  void initState() {
    super.initState();
    final q = ref.read(stockListQueryProvider);
    final op = ref.read(stockOperationalFiltersProvider);
    _sort = q.sort;
    _category = '';
    _supplier = q.supplier;
    _missingBarcode = op.missingBarcodeOnly;
    _missingItemCode = op.missingItemCodeOnly;
    _reorderOnly = op.reorderOnly;
    _purchasedInPeriodOnly = op.purchasedInPeriodOnly;
    _unit = op.unit;
    _subcatField = TextEditingController(
      text: widget.subcategoryCtrl?.text ?? q.subcategory,
    );
  }

  @override
  void dispose() {
    _subcatField.dispose();
    super.dispose();
  }

  void _apply() {
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(
              sort: _sort,
              category: '',
              supplier: _supplier,
              subcategory: _subcatField.text.trim(),
              purchasedInPeriod: _purchasedInPeriodOnly,
              page: 1,
            );
    ref.read(stockOperationalFiltersProvider.notifier).state =
        StockOperationalFilters(
      missingBarcodeOnly: _missingBarcode,
      missingItemCodeOnly: _missingItemCode,
      reorderOnly: _reorderOnly,
      purchasedInPeriodOnly: _purchasedInPeriodOnly,
      unit: _unit,
    );
    ref.read(stockSelectedItemIdProvider.notifier).state = null;
    widget.subcategoryCtrl?.text = _subcatField.text.trim();
    Navigator.pop(context);
  }

  void _clear() {
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(
              category: '',
              subcategory: '',
              supplier: '',
              sort: 'name',
              page: 1,
            );
    ref.read(stockOperationalFiltersProvider.notifier).state =
        StockOperationalFilters(
            unit: ref.read(stockOperationalFiltersProvider).unit);
    widget.subcategoryCtrl?.clear();
    _subcatField.clear();
    setState(() {
      _sort = 'name';
      _category = '';
      _supplier = '';
      _missingBarcode = false;
      _missingItemCode = false;
      _reorderOnly = false;
      _purchasedInPeriodOnly = false;
    });
  }

  List<String> _subcategoryOptions(List<Map<String, dynamic>> types) {
    final out = <String>[];
    for (final t in types) {
      final name = (t['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      out.add(name);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  Future<void> _pickSupplier(List<Map<String, dynamic>> rows) async {
    final pickRows = <SearchPickerRow<String>>[
      for (final s in rows)
        if ((s['name'] ?? '').toString().trim().isNotEmpty)
          SearchPickerRow<String>(
            value: s['name'].toString().trim(),
            title: s['name'].toString().trim(),
            subtitle: s['phone']?.toString(),
          ),
    ]..sort((a, b) => a.title.compareTo(b.title));
    final picked = await showSearchPickerSheet<String>(
      context: context,
      title: 'Select supplier',
      rows: pickRows,
      selectedValue: _supplier.isEmpty ? null : _supplier,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _supplier = picked);
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersListProvider);
    final typesAsync = ref.watch(categoryTypesIndexProvider);

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(
          HexaOp.pageGutter,
          12,
          HexaOp.pageGutter,
          24 + bottomInset + widget.bottomNavInset,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
        Text(
          'Filters',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
        ),
        const SizedBox(height: 12),
        const Text('Stock status',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final e in [
              ('Low', 'low'),
              ('Critical', 'critical'),
              ('Out', 'out'),
            ])
              FilterChip(
                label: Text(e.$1, style: const TextStyle(fontSize: 12)),
                selected: ref.read(stockListQueryProvider).status == e.$2,
                onSelected: (_) {
                  final q = ref.read(stockListQueryProvider);
                  final on = q.status == e.$2;
                  ref.read(stockListQueryProvider.notifier).state = q.copyWith(
                    status: on ? 'all' : e.$2,
                    page: 1,
                  );
                  ref.read(stockOperationalFiltersProvider.notifier).state =
                      ref.read(stockOperationalFiltersProvider).copyWith(
                            reorderOnly: false,
                            clearMissingItemCode: true,
                          );
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reorder only', style: TextStyle(fontSize: 14)),
          value: _reorderOnly,
          onChanged: (v) => setState(() => _reorderOnly = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Purchased in period',
            style: TextStyle(fontSize: 14),
          ),
          value: _purchasedInPeriodOnly,
          onChanged: (v) => setState(() => _purchasedInPeriodOnly = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Missing barcode', style: TextStyle(fontSize: 14)),
          value: _missingBarcode,
          onChanged: (v) => setState(() => _missingBarcode = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              const Text('Missing item code', style: TextStyle(fontSize: 14)),
          value: _missingItemCode,
          onChanged: (v) => setState(() => _missingItemCode = v),
        ),
        const SizedBox(height: 8),
        typesAsync.when(
          loading: () => TextField(
            controller: _subcatField,
            decoration: const InputDecoration(
              labelText: 'Subcategory',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          error: (_, __) => TextField(
            controller: _subcatField,
            decoration: const InputDecoration(
              labelText: 'Subcategory',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          data: (types) {
            final options = _subcategoryOptions(types);
            final items = options
                .map(
                  (label) => InlineSearchItem(
                    id: label,
                    label: label,
                    subtitle: _category.isEmpty ? null : _category,
                    searchText: '$label $_category',
                  ),
                )
                .toList();
            return InlineSearchField(
              items: items,
              controller: _subcatField,
              placeholder: 'All subcategories',
              textInputAction: TextInputAction.next,
              onSelected: (item) {
                _subcatField.text = item.label;
                setState(() {});
              },
            );
          },
        ),
        if (widget.includeSupplier) ...[
          const SizedBox(height: 12),
          Text('Supplier', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          suppliersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              return Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _pickSupplier(rows),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _supplier.isEmpty
                                      ? 'All suppliers'
                                      : _supplier,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: Colors.black45,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Search supplier',
                    onPressed: () => _pickSupplier(rows),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  if (_supplier.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear supplier',
                      onPressed: () => setState(() => _supplier = ''),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              );
            },
          ),
          if (!widget.isStaffMode)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/contacts');
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add supplier'),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text('Unit', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in ['BAG', 'KG', 'BOX', 'TIN', 'PIECE'])
              FilterChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                selected: _unit == label.toLowerCase(),
                onSelected: (on) => setState(() {
                  _unit = on ? label.toLowerCase() : '';
                }),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Sort', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _sort,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Name A–Z')),
            DropdownMenuItem(value: 'stock_asc', child: Text('Stock ↑')),
            DropdownMenuItem(value: 'stock_desc', child: Text('Stock ↓')),
            DropdownMenuItem(value: 'recent', child: Text('Recent')),
          ],
          onChanged: (v) => setState(() => _sort = v ?? 'name'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
        TextButton(onPressed: _clear, child: const Text('Clear advanced')),
        if (!widget.isStaffMode) ...[
          const Divider(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showStockBulkActionsSheet(context: context, ref: ref);
            },
            icon: const Icon(Icons.layers_outlined, size: 18),
            label: const Text('Barcode bulk print'),
          ),
        ],
        ],
      ),
    );
  }
}

String stockActiveFilterSummary(StockListQuery q, StockOperationalFilters op) {
  final parts = <String>[];
  if (q.category.isNotEmpty) parts.add(q.category);
  if (q.subcategory.isNotEmpty) parts.add(q.subcategory);
  if (q.supplier.isNotEmpty) parts.add(q.supplier);
  if (q.status == 'low') parts.add('Low');
  if (q.status == 'critical') parts.add('Critical');
  if (q.status == 'out') parts.add('Out');
  if (op.missingBarcodeOnly) parts.add('No barcode');
  if (op.missingItemCodeOnly) parts.add('No code');
  if (op.reorderOnly) parts.add('Reorder');
  if (op.purchasedInPeriodOnly) parts.add('Purchased');
  if (op.unit.isNotEmpty) parts.add(op.unit.toUpperCase());
  if (q.sort == 'recent') parts.add('Recent');
  return parts.join(' · ');
}
