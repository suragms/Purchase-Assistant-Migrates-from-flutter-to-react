import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';

/// Full-height draggable preview before opening catalog item detail.
Future<void> showItemQuickView({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (sheetCtx, scrollCtrl) => _ItemQuickViewBody(
        itemId: itemId,
        itemName: itemName,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _ItemQuickViewBody extends ConsumerStatefulWidget {
  const _ItemQuickViewBody({
    required this.itemId,
    required this.itemName,
    required this.scrollController,
  });

  final String itemId;
  final String itemName;
  final ScrollController scrollController;

  @override
  ConsumerState<_ItemQuickViewBody> createState() => _ItemQuickViewBodyState();
}

class _ItemQuickViewBodyState extends ConsumerState<_ItemQuickViewBody> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _searchStockList() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    ref.read(stockListQueryProvider.notifier).state =
        ref.read(stockListQueryProvider).copyWith(q: q, page: 1, sort: 'recent');
    Navigator.of(context).pop();
    context.push('/stock');
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockItemDetailProvider(widget.itemId));
    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.heading(18),
                ),
              ),
              IconButton(
                tooltip: 'Open full page',
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/catalog/item/${widget.itemId}');
                },
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: stockAsync.when(
            loading: () => const ListSkeleton(rowCount: 4),
            error: (_, __) => FriendlyLoadError(
              message: 'Could not load stock',
              onRetry: () => ref.invalidate(stockItemDetailProvider(widget.itemId)),
            ),
            data: (stock) {
              final item = itemAsync.valueOrNull ?? const <String, dynamic>{};
              final unit = (stock['stock_unit'] ?? stock['unit'] ?? item['default_unit'] ?? 'bag')
                  .toString();
              final cur = coerceToDouble(stock['current_stock']);
              final reorder = coerceToDouble(stock['reorder_level']);
              final status = stockDisplayStatusFromApi(
                stock['stock_status']?.toString(),
              );
              final code = item['item_code']?.toString().trim() ?? '';
              final category = [
                item['category_name'],
                item['subcategory_name'] ?? item['type_name'],
              ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

              return ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search another item…',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: _searchStockList,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchStockList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          HexaColors.brandPrimary.withValues(alpha: 0.12),
                          HexaColors.brandPrimary.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: HexaColors.brandPrimary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ON HAND',
                          style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                        ),
                        const SizedBox(height: 8),
                        StockNumberDisplay(
                          qty: cur,
                          unit: unit,
                          status: status,
                          hasPendingOrder: stock['has_pending_order'] == true,
                          pendingDays:
                              (stock['pending_order_days'] as num?)?.toInt(),
                          fontSize: 28,
                        ),
                        if (reorder > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Reorder at ${formatStockQtyNumber(reorder)} ${unit.toUpperCase()}',
                            style: HexaDsType.body(13, color: HexaDsColors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (code.isNotEmpty)
                    _InfoRow(label: 'Item code', value: code),
                  if (category.isNotEmpty)
                    _InfoRow(label: 'Category', value: category),
                  if ((stock['supplier_name'] ?? item['supplier_name'])
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true)
                    _InfoRow(
                      label: 'Supplier',
                      value: (stock['supplier_name'] ?? item['supplier_name'])
                          .toString(),
                      valueBold: true,
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/catalog/item/${widget.itemId}');
                    },
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Open full item page'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/barcode/print/${widget.itemId}');
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print label'),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueBold = false,
  });

  final String label;
  final String value;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: HexaDsType.body(12, color: HexaDsColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
