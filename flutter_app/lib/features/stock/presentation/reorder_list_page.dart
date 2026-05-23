import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/reorder_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
class ReorderListPage extends ConsumerStatefulWidget {
  const ReorderListPage({super.key});

  @override
  ConsumerState<ReorderListPage> createState() => _ReorderListPageState();
}

class _ReorderListPageState extends ConsumerState<ReorderListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _statuses = ['pending', 'ordered', 'done'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    await ref.read(hexaApiProvider).patchReorderEntry(
          businessId: session.primaryBusiness.id,
          entryId: id,
          status: status,
        );
    ref.invalidate(reorderListProvider);
    ref.invalidate(reorderPendingCountProvider);
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    await ref.read(hexaApiProvider).deleteReorderEntry(
          businessId: session.primaryBusiness.id,
          entryId: id,
        );
    ref.invalidate(reorderListProvider);
    ref.invalidate(reorderPendingCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final pendingN = ref.watch(reorderPendingCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reorder list'),
            Text(
              '$pendingN pending',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Ordered'),
            Tab(text: 'Done'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final st in _statuses) _ReorderTab(status: st, onSetStatus: _setStatus, onRemove: _remove),
        ],
      ),
    );
  }
}

class _ReorderTab extends ConsumerWidget {
  const _ReorderTab({
    required this.status,
    required this.onSetStatus,
    required this.onRemove,
  });

  final String status;
  final Future<void> Function(Map<String, dynamic> row, String status) onSetStatus;
  final Future<void> Function(Map<String, dynamic> row) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reorderListProvider(status));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => FriendlyLoadError(
        message: 'Could not load reorder list',
        subtitle: 'Please check your connection and try again.',
        onRetry: () => ref.invalidate(reorderListProvider(status)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    status == 'pending'
                        ? 'No pending reorders'
                        : 'No $status items',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add items from stock or item detail',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reorderListProvider(status));
            await ref.read(reorderListProvider(status).future);
          },
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              0,
              96 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final itemId = r['item_id']?.toString() ?? '';
              final name = r['item_name']?.toString() ?? '—';
              final cur = r['current_stock']?.toString() ?? '—';
              final ro = r['reorder_level']?.toString() ?? '—';
              final unit = r['unit']?.toString() ?? '';
              final supplier = r['supplier_name']?.toString().trim() ?? '';
              final lastRate = r['last_purchase_rate'];
              final rateStr = lastRate is num && lastRate > 0
                  ? NumberFormat.currency(
                      locale: 'en_IN',
                      symbol: '₹',
                      decimalDigits: 0,
                    ).format(lastRate)
                  : '';
              final by = r['added_by_name']?.toString() ?? '—';
              final created = r['created_at']?.toString();
              DateTime? dt;
              if (created != null) dt = DateTime.tryParse(created);
              final ago = dt != null
                  ? DateFormat('d MMM').format(dt.toLocal())
                  : '';

              return Material(
                color: status == 'done'
                    ? Colors.grey.shade50
                    : Colors.white,
                child: InkWell(
                  onTap: itemId.isEmpty
                      ? null
                      : () => context.push('/catalog/item/$itemId'),
                  onLongPress: () async {
                    final action = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder: (c) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status == 'pending')
                              ListTile(
                                leading: const Icon(Icons.local_shipping_outlined),
                                title: const Text('Mark ordered'),
                                onTap: () => Navigator.pop(c, 'ordered'),
                              ),
                            if (status == 'ordered')
                              ListTile(
                                leading: const Icon(Icons.check_rounded),
                                title: const Text('Mark done'),
                                onTap: () => Navigator.pop(c, 'done'),
                              ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: const Text('Remove from list'),
                              onTap: () => Navigator.pop(c, 'remove'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (action == 'ordered') await onSetStatus(r, 'ordered');
                    if (action == 'done') await onSetStatus(r, 'done');
                    if (action == 'remove') await onRemove(r);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (status) {
                              'pending' => const Color(0xFFE65100),
                              'ordered' => HexaColors.brandPrimary,
                              _ => Colors.grey,
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: status == 'done'
                                      ? Colors.grey.shade600
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                [
                                  'Stock $cur / reorder $ro${unit.isNotEmpty ? ' $unit' : ''}',
                                  if (supplier.isNotEmpty) supplier,
                                  if (rateStr.isNotEmpty) 'Last $rateStr',
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                'Added by $by · $ago',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (status == 'pending') ...[
                          TextButton(
                            onPressed: () {
                              final itemId = r['item_id']?.toString() ??
                                  r['catalog_item_id']?.toString() ??
                                  '';
                              if (itemId.isEmpty) return;
                              context.push(
                                '/purchase/new?catalogItemId=${Uri.encodeComponent(itemId)}',
                              );
                            },
                            child: const Text('Order'),
                          ),
                          TextButton(
                            onPressed: () => onSetStatus(r, 'ordered'),
                            child: const Text('Ordered'),
                          ),
                        ],
                        if (status == 'ordered')
                          TextButton(
                            onPressed: () => onSetStatus(r, 'done'),
                            child: const Text('Done'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
