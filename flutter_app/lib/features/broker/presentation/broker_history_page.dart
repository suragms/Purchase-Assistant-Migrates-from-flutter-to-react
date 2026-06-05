import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/broker_statement_pdf.dart';
import '../../../core/utils/line_display.dart';
import '../../purchase/state/purchase_providers.dart';

final _brokerHistoryHeaderProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, brokerId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getBroker(
        businessId: session.primaryBusiness.id,
        brokerId: brokerId,
      );
});

class BrokerHistoryPage extends ConsumerWidget {
  const BrokerHistoryPage({super.key, required this.brokerId});

  final String brokerId;

  String _inr(num n) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: n % 1 == 0 ? 0 : 2,
      ).format(n);

  String _fmtQty(double q) =>
      (q - q.roundToDouble()).abs() < 1e-6 ? '${q.round()}' : q.toStringAsFixed(1);

  Widget _summaryCard(BuildContext context, LedgerLinesState s) {
    final rows = s.filtered();
    final deals = rows.map((e) => e.purchaseId).toSet().length;
    final comm = rows.fold<double>(0, (a, r) => a + r.commissionInr);
    var kg = 0.0;
    var bags = 0.0;
    var boxes = 0.0;
    var tins = 0.0;
    for (final r in rows) {
      kg += r.kg;
      final u = r.unit.trim().toLowerCase();
      if (u == 'bag' || u == 'sack') bags += r.qty;
      if (u == 'box') boxes += r.qty;
      if (u == 'tin') tins += r.qty;
    }
    final parts = <String>[
      if (kg > 1e-9) '${_fmtQty(kg)} kg',
      if (bags > 1e-9) '${_fmtQty(bags)} bags',
      if (boxes > 1e-9) '${_fmtQty(boxes)} boxes',
      if (tins > 1e-9) '${_fmtQty(tins)} tins',
    ];
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Deals (filtered) $deals',
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text('Commission Σ ${_inr(comm)}',
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                parts.join(' · '),
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowCard(
    BuildContext context,
    WidgetRef ref,
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
    return InkWell(
      onTap: () => context.push('/purchase/detail/${row.purchaseId}'),
      onLongPress: () => _openRowActions(context, ref, row),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
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
                        row.itemName.isEmpty ? '—' : row.itemName,
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
                        '${row.supplierName.isEmpty ? '—' : row.supplierName} · ${row.humanId ?? row.purchaseId} · ${fmt.format(row.purchaseDate)}',
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
                      'Comm ${_inr(row.commissionInr)}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      ref.invalidate(brokerHistoryLinesProvider(brokerId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is DioException ? friendlyApiError(e) : 'Could not delete')),
      );
    }
  }

  Widget _metrics(BuildContext context, LedgerLinesState s) {
    return _summaryCard(context, s);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(brokerHistoryLinesProvider(brokerId));
    final headerAsync = ref.watch(_brokerHistoryHeaderProvider(brokerId));
    final purchasesAsync = ref.watch(tradePurchasesParsedProvider);
    final fmt = DateFormat.yMMMd();
    final notifier = ref.read(brokerHistoryLinesProvider(brokerId).notifier);

    final showLoadMore =
        !state.loadingInitial && (state.canRevealMoreLocally || !state.exhausted);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Broker history'),
        actions: [
          IconButton(
            tooltip: 'Commission statement (PDF)',
            onPressed: () async {
              final biz = ref.read(invoiceBusinessProfileProvider);
              final header = headerAsync.asData?.value;
              final brokerName =
                  (header?['name'] ?? header?['display_name'])?.toString().trim();
              final brokerPhone = header?['phone']?.toString().trim();

              final merged = purchasesAsync.asData?.value;
              if (merged == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loading purchases… try again in a moment')),
                );
                return;
              }

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final seedFrom = today.subtract(const Duration(days: 29));
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: DateTimeRange(start: seedFrom, end: today),
              );
              if (picked == null) return;
              final from = DateTime(picked.start.year, picked.start.month, picked.start.day);
              final to = DateTime(picked.end.year, picked.end.month, picked.end.day);

              final filtered = merged.where((p) {
                if (p.brokerId == null || p.brokerId!.isEmpty) return false;
                if (p.brokerId != brokerId) return false;
                final d = DateTime(p.purchaseDate.year, p.purchaseDate.month, p.purchaseDate.day);
                return !d.isBefore(from) && !d.isAfter(to);
              }).toList();

              if (filtered.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No broker purchases in this period')),
                );
                return;
              }

              await shareBrokerStatementPdfForChat(
                business: biz,
                brokerName: (brokerName != null && brokerName.isNotEmpty)
                    ? brokerName
                    : 'Broker',
                brokerPhone: brokerPhone,
                purchases: filtered,
                fromDate: from,
                toDate: to,
              );
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      (name != null && name.isNotEmpty) ? name : 'Broker',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search item, supplier, invoice (PUR-…), id…',
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
                          itemCount: state.visibleRows().length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) =>
                              _rowCard(context, ref, state.visibleRows()[i], fmt),
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
