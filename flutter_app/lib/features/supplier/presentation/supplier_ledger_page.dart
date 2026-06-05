import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import '../../purchase/state/purchase_providers.dart';

final _supplierLedgerHeaderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, supplierId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getSupplier(
        businessId: session.primaryBusiness.id,
        supplierId: supplierId,
      );
});

class SupplierLedgerPage extends ConsumerWidget {
  const SupplierLedgerPage({super.key, required this.supplierId});

  final String supplierId;

  String _inr(num n) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: n % 1 == 0 ? 0 : 2,
      ).format(n);

  Map<String, dynamic> _rowIntel(LedgerLineRow row) {
    final u = row.unit.trim().toLowerCase();
    double? kpu;
    if ((u == 'bag' || u == 'sack' || u == 'box' || u == 'tin') &&
        row.qty > 1e-9 &&
        row.kg > 1e-9) {
      kpu = row.kg / row.qty;
    }
    return {
      'last_purchase_price': row.rateInr,
      'last_selling_rate': row.sellingRateInr,
      'last_line_qty': row.qty,
      'last_line_unit': row.unit,
      'last_line_weight_kg': row.kg,
      if (kpu != null) 'kg_per_unit': kpu,
      if (row.purchaseRateDim.isNotEmpty) 'purchase_rate_dim': row.purchaseRateDim,
      if (row.sellingRateDim.isNotEmpty) 'selling_rate_dim': row.sellingRateDim,
    };
  }

  Future<void> _openRowActions(BuildContext context, WidgetRef ref, LedgerLineRow row) async {
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
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
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
      invalidateAfterPurchaseDelete(ref, purchaseId: row.purchaseId);
      ref.invalidate(supplierLedgerLinesProvider(supplierId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is DioException ? friendlyApiError(e) : 'Could not delete'),
        ),
      );
    }
  }

  Widget _metrics(BuildContext context, LedgerLinesState s) {
    final rows = s.filtered();
    final deals = rows.map((e) => e.purchaseId).toSet().length;
    final amt = rows.fold<double>(0, (a, r) => a + r.amountInr);
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Deals (filtered) $deals', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('Amount ${_inr(amt)}', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(supplierLedgerLinesProvider(supplierId));
    final headerAsync = ref.watch(_supplierLedgerHeaderProvider(supplierId));
    final fmt = DateFormat.yMMMd();
    final notifier = ref.read(supplierLedgerLinesProvider(supplierId).notifier);

    final showLoadMore =
        !state.loadingInitial && (state.canRevealMoreLocally || !state.exhausted);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Supplier ledger'),
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
              headerAsync.maybeWhen(
                data: (m) {
                  final name = (m['name'] ?? m['display_name'])?.toString().trim();
                  final phone =
                      (m['phone'] ?? m['mobile'] ?? m['whatsapp'])?.toString().trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name != null && name.isNotEmpty)
                          Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              )),
                        if (phone != null && phone.isNotEmpty)
                          Text(phone,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )),
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search item, invoice (PUR-…), id…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 22),
                  border: OutlineInputBorder(),
                ),
                onChanged: notifier.setSearchTyping,
              ),
              const SizedBox(height: 12),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              _metrics(context, state),
              if (state.loadingInitial && state.rows.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else ...[
                Expanded(
                  child: state.visibleRows().isEmpty
                      ? const Center(child: Text('No matching lines'))
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 4),
                          itemCount: state.visibleRows().length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final row = state.visibleRows()[i];
                            final intel = _rowIntel(row);
                            final qtyLine = tradeIntelQtySummaryLine(intel);
                            final rateLine = tradeIntelRatePairLine(intel);
                            final tt = Theme.of(context).textTheme;
                            final cs = Theme.of(context).colorScheme;
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: cs.outlineVariant.withValues(alpha: 0.85),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () =>
                                    context.push('/purchase/detail/${row.purchaseId}'),
                                onLongPress: () =>
                                    _openRowActions(context, ref, row),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row.itemName,
                                              style: tt.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _inr(row.amountInr),
                                            style: tt.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${fmt.format(row.purchaseDate)} · '
                                        '${row.humanId ?? row.purchaseId}',
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (qtyLine.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          qtyLine,
                                          style: tt.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (rateLine.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          rateLine,
                                          style: tt.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      if (row.supplierName.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'From: ${row.supplierName}',
                                          style: tt.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more_rounded),
                        label: Text(state.loadingMore ? 'Loading…' : 'Load more'),
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
