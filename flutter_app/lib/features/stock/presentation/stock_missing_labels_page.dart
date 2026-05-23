import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import 'widgets/assign_barcode_sheet.dart';
import 'widgets/edit_item_code_sheet.dart';

class StockMissingLabelsPage extends ConsumerStatefulWidget {
  const StockMissingLabelsPage({super.key});

  @override
  ConsumerState<StockMissingLabelsPage> createState() =>
      _StockMissingLabelsPageState();
}

class _StockMissingLabelsPageState extends ConsumerState<StockMissingLabelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(bulkStockListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Missing labels'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Missing barcode'),
            Tab(text: 'Missing item code'),
          ],
        ),
      ),
      body: listAsync.when(
        loading: () => const ListSkeleton(rowCount: 10, rowHeight: 64),
        error: (_, __) => FriendlyLoadError(
          onRetry: () => ref.invalidate(bulkStockListProvider),
        ),
        data: (blob) {
          final items = [
            for (final row in (blob['items'] as List? ?? []))
              if (row is Map) Map<String, dynamic>.from(row),
          ];
          int byStockDesc(Map<String, dynamic> a, Map<String, dynamic> b) =>
              coerceToDouble(b['current_stock'])
                  .compareTo(coerceToDouble(a['current_stock']));
          final missingBarcode = items
              .where((it) => it['missing_barcode'] == true)
              .toList()
            ..sort(byStockDesc);
          final missingCode = items
              .where((it) => it['missing_item_code'] == true)
              .toList()
            ..sort(byStockDesc);
          return TabBarView(
            controller: _tabs,
            children: [
              _list(context, ref, missingBarcode, isBarcodeTab: true),
              _list(context, ref, missingCode, isBarcodeTab: false),
            ],
          );
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> rows, {
    required bool isBarcodeTab,
  }) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          isBarcodeTab
              ? 'All items have packaging barcodes'
              : 'All items have internal codes',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: HexaOp.pageGutter,
        vertical: 8,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final it = rows[i];
        final id = it['id']?.toString() ?? '';
        final name = it['name']?.toString() ?? 'Item';
        final unit = it['unit']?.toString() ?? '';
        final cur = coerceToDouble(it['current_stock']);
        final code = it['item_code']?.toString() ?? '—';
        final bc = it['barcode']?.toString();
        final subtitle = isBarcodeTab
            ? 'Stock: ${stockDisplayPrimary(cur, unit)} · Code: $code'
            : 'Stock: ${stockDisplayPrimary(cur, unit)} · Barcode: ${bc ?? '—'}';
        return SizedBox(
          height: HexaOp.listRowMin,
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: id.isEmpty
                  ? null
                  : () => context.push('/catalog/item/$id'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isBarcodeTab ? 'Assign barcode' : 'Edit item code',
                      icon: Icon(isBarcodeTab ? Icons.link : Icons.edit_outlined),
                      onPressed: id.isEmpty
                          ? null
                          : () async {
                              if (isBarcodeTab) {
                                await showAssignBarcodeSheet(
                                  context: context,
                                  ref: ref,
                                  itemId: id,
                                  itemName: name,
                                );
                              } else {
                                await showEditItemCodeSheet(
                                  context: context,
                                  ref: ref,
                                  itemId: id,
                                  itemName: name,
                                  currentCode: it['item_code']?.toString(),
                                );
                              }
                              ref.invalidate(bulkStockListProvider);
                              ref.invalidate(stockListProvider);
                            },
                    ),
                    IconButton(
                      tooltip: 'Print label',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: id.isEmpty
                          ? null
                          : () => context.push(
                                '/barcode/print/${Uri.encodeComponent(id)}',
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
