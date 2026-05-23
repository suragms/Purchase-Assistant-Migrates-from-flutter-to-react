import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/catalog_providers.dart'
    show catalogItemDetailProvider, catalogItemsListProvider;
import '../../../core/providers/staff_home_providers.dart'
    show missingCodeItemsProvider;
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

/// Items without item_code — generate ITM-#### and print labels.
class CatalogMissingCodesPage extends ConsumerStatefulWidget {
  const CatalogMissingCodesPage({super.key});

  @override
  ConsumerState<CatalogMissingCodesPage> createState() =>
      _CatalogMissingCodesPageState();
}

class _CatalogMissingCodesPageState extends ConsumerState<CatalogMissingCodesPage> {
  final _busy = <String>{};

  Future<void> _generateCode(String itemId, String name) async {
    final session = ref.read(sessionProvider);
    if (session == null || _busy.contains(itemId)) return;
    setState(() => _busy.add(itemId));
    try {
      final out = await ref.read(hexaApiProvider).generateCatalogItemCode(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      ref.invalidate(missingCodeItemsProvider);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(bulkStockListProvider);
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(catalogItemDetailProvider(itemId));
      if (!mounted) return;
      final code = out['item_code']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name · code ${code.isEmpty ? 'assigned' : code}'),
          action: SnackBarAction(
            label: 'Print label',
            onPressed: () => context.push(
              '/barcode/print/${Uri.encodeComponent(itemId)}',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(itemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(missingCodeItemsProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Missing item codes'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: listAsync.when(
        loading: () => const ListSkeleton(rowCount: 10, rowHeight: 64),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load items',
          onRetry: () => ref.invalidate(missingCodeItemsProvider),
        ),
        data: (rawRows) {
          final rows = List<Map<String, dynamic>>.from(rawRows)
            ..sort(
              (a, b) => coerceToDouble(b['current_stock'])
                  .compareTo(coerceToDouble(a['current_stock'])),
            );
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'All items have codes assigned.',
                  style: HexaDsType.body(15, color: HexaDsColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final it = rows[i];
              final id = it['id']?.toString() ?? '';
              final name = it['name']?.toString() ?? 'Item';
              final cat = it['category_name']?.toString() ?? '';
              final busy = _busy.contains(id);
              return Card(
                child: ListTile(
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: cat.isEmpty ? const Text('No barcode code') : Text(cat),
                  trailing: busy
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: id.isEmpty
                                  ? null
                                  : () => _generateCode(id, name),
                              child: const Text('Generate'),
                            ),
                            IconButton(
                              tooltip: 'Print label',
                              onPressed: id.isEmpty
                                  ? null
                                  : () => context.push(
                                        '/barcode/print/${Uri.encodeComponent(id)}',
                                      ),
                              icon: const Icon(Icons.print_outlined),
                            ),
                          ],
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
