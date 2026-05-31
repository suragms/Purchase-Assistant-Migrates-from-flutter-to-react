import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/widgets/focused_search_chrome.dart';
import '../../purchase/providers/trade_purchase_detail_provider.dart';
import '../../purchase/state/purchase_providers.dart';

class ItemHistoryPage extends ConsumerStatefulWidget {
  const ItemHistoryPage({super.key, required this.catalogItemId});

  final String catalogItemId;

  @override
  ConsumerState<ItemHistoryPage> createState() => _ItemHistoryPageState();
}

class _ItemHistoryPageState extends ConsumerState<ItemHistoryPage> {
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(itemHistoryLinesProvider(widget.catalogItemId));
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String _kg(num n) => NumberFormat('#,##,##0.##', 'en_IN').format(n);

  String _inr(num n) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: n % 1 == 0 ? 0 : 2,
      ).format(n);

  Widget _rowCard(
    BuildContext context,
    LedgerLineRow row,
    DateFormat fmt,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final uRaw = row.unit.trim().toLowerCase();
    final u = uRaw == 'sack' ? 'bag' : uRaw;
    final qtySummary = (u == 'bag')
        ? formatPackagedQty(unit: 'bag', pieces: row.qty, kg: row.kg)
        : (u == 'box')
            ? formatPackagedQty(unit: 'box', pieces: row.qty)
            : (u == 'tin')
                ? formatPackagedQty(unit: 'tin', pieces: row.qty)
                : formatLineQtyWeight(
                    qty: row.qty,
                    unit: row.unit,
                    totalWeightKg: row.kg > 1e-9 ? row.kg : null,
                    kgPerUnit: null,
                  );
    final d = row.purchaseRateDim.trim();
    final rateSuffix = d.isNotEmpty
        ? '/$d'
        : '/${row.unit.trim().isEmpty ? 'unit' : row.unit.trim()}';
    return InkWell(
      onTap: () => context.push('/purchase/detail/${row.purchaseId}'),
      onLongPress: () => _openRowActions(context, row),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.supplierName.isEmpty ? '—' : row.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    qtySummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row.humanId ?? row.purchaseId} · ${fmt.format(row.purchaseDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _inr(row.amountInr),
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_inr(row.rateInr)}$rateSuffix',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (row.kg > 1e-9) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_kg(row.kg)} kg',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRowActions(
    BuildContext context,
    LedgerLineRow row,
  ) async {
    if (!context.mounted) return;
    final action = await showHexaBottomSheet<String>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      context.push('/purchase/edit/${row.purchaseId}');
      return;
    }
    if (action != 'delete') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove bill ${row.humanId ?? row.purchaseId}?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => ctx.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: row.purchaseId,
          );
      invalidateAfterPurchaseDelete(
        ref,
        purchaseId: row.purchaseId,
        extraItemIds: {widget.catalogItemId},
      );
      ref.invalidate(itemHistoryLinesProvider(widget.catalogItemId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is DioException
                ? friendlyApiError(e)
                : 'Could not delete')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemHistoryLinesProvider(widget.catalogItemId));
    final itemAsync = ref.watch(catalogItemDetailProvider(widget.catalogItemId));
    final fmt = DateFormat.yMMMd();
    final notifier =
        ref.read(itemHistoryLinesProvider(widget.catalogItemId).notifier);

    final showLoadMore = !state.loadingInitial &&
        (state.canRevealMoreLocally || !state.exhausted);

    final searchActive = _searchFocus.hasFocus ||
        state.searchTyping.trim().isNotEmpty ||
        state.searchEffective.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Item history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.loadingInitial ? null : () => notifier.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  hintText: 'Search supplier, invoice (PUR-…), id…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 22),
                  border: OutlineInputBorder(),
                ),
                onChanged: notifier.setSearchTyping,
              ),
              const SizedBox(height: 12),
              CollapsibleSearchChrome(
                searchActive: searchActive,
                chrome: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    itemAsync.maybeWhen(
                      data: (m) {
                        final name = m['name']?.toString().trim() ?? 'Item';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (state.loadingInitial && state.rows.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else ...[
                Expanded(
                  child: state.visibleRows().isEmpty
                      ? const Center(child: Text('No matching lines'))
                      : ListView.separated(
                          itemCount: state.visibleRows().length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) => _rowCard(
                            context,
                            state.visibleRows()[i],
                            fmt,
                          ),
                        ),
                ),
                if (showLoadMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: FilledButton.tonalIcon(
                        onPressed: (state.loadingInitial || state.loadingMore)
                            ? null
                            : () => notifier.loadMore(),
                        icon: state.loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(
                            state.loadingMore ? 'Loading…' : 'Load more'),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
