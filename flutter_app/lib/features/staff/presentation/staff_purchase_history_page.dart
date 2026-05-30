import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/auth_failure_policy.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../purchase/presentation/widgets/purchase_history_grouping.dart';
import 'widgets/staff_purchase_history_row.dart';

enum _PurchaseStatusFilter { all, pending, delivered }

enum _LowStockFilter { all, critical }

/// Staff purchase list — same layout as owner history, no prices.
class StaffPurchaseHistoryPage extends ConsumerStatefulWidget {
  const StaffPurchaseHistoryPage({super.key});

  @override
  ConsumerState<StaffPurchaseHistoryPage> createState() =>
      _StaffPurchaseHistoryPageState();
}

class _StaffPurchaseHistoryPageState extends ConsumerState<StaffPurchaseHistoryPage>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  late final TabController _tabs;
  String _query = '';
  _PurchaseStatusFilter _statusFilter = _PurchaseStatusFilter.all;
  _LowStockFilter _lowFilter = _LowStockFilter.all;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  StaffPurchaseHistoryPeriod get _period => switch (_tabs.index) {
        0 => StaffPurchaseHistoryPeriod.today,
        1 => StaffPurchaseHistoryPeriod.week,
        2 => StaffPurchaseHistoryPeriod.allTime,
        _ => StaffPurchaseHistoryPeriod.allTime,
      };

  List<TradePurchase> _filterPurchases(List<TradePurchase> all) {
    return all.where((p) {
      if (_statusFilter == _PurchaseStatusFilter.pending && p.isDelivered) {
        return false;
      }
      if (_statusFilter == _PurchaseStatusFilter.delivered && !p.isDelivered) {
        return false;
      }
      if (_query.isEmpty) return true;
      final hay = [
        p.humanId,
        p.supplierName ?? '',
        for (final l in p.lines) l.itemName,
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  List<Map<String, dynamic>> _filterLowStock(List<Map<String, dynamic>> rows) {
    return rows.where((item) {
      if (_lowFilter == _LowStockFilter.critical) {
        final cur = coerceToDouble(item['current_stock']);
        final reorder = coerceToDouble(item['reorder_level']);
        if (reorder <= 0 || cur > reorder * 0.5) return false;
      }
      if (_query.isEmpty) return true;
      final name = item['name']?.toString().toLowerCase() ?? '';
      return name.contains(_query);
    }).toList();
  }

  String _loadErrorMessage(Object error) {
    if (ref.read(authSessionExpiredProvider)) {
      return 'Session expired — sign in again';
    }
    if (error is DioException) return friendlyApiError(error);
    return 'Could not load purchase history';
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs.index;
    final lowAsync = ref.watch(staffLowStockAlertsProvider);
    final purchasesAsync = tab < 3
        ? ref.watch(staffTradePurchasesHistoryProvider(_period))
        : null;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Purchase orders'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          onTap: (_) => setState(() {}),
          tabs: [
            const Tab(text: 'Today'),
            const Tab(text: 'Week'),
            const Tab(text: 'All time'),
            Tab(
              text: lowAsync.maybeWhen(
                data: (rows) => 'Low stock (${rows.length})',
                orElse: () => 'Low stock',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: tab == 3
                    ? 'Search low stock items…'
                    : 'Search supplier, ID, items…',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: HexaColors.brandBorder),
                ),
              ),
            ),
          ),
          if (tab < 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    label: const Text('All', style: TextStyle(fontSize: 11)),
                    selected: _statusFilter == _PurchaseStatusFilter.all,
                    onSelected: (_) => setState(
                      () => _statusFilter = _PurchaseStatusFilter.all,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  FilterChip(
                    label: const Text('Undelivered', style: TextStyle(fontSize: 11)),
                    selected: _statusFilter == _PurchaseStatusFilter.pending,
                    onSelected: (_) => setState(
                      () => _statusFilter = _PurchaseStatusFilter.pending,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  FilterChip(
                    label: const Text('Delivered', style: TextStyle(fontSize: 11)),
                    selected: _statusFilter == _PurchaseStatusFilter.delivered,
                    onSelected: (_) => setState(
                      () => _statusFilter = _PurchaseStatusFilter.delivered,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                children: [
                  FilterChip(
                    label: const Text('All low', style: TextStyle(fontSize: 11)),
                    selected: _lowFilter == _LowStockFilter.all,
                    onSelected: (_) =>
                        setState(() => _lowFilter = _LowStockFilter.all),
                    visualDensity: VisualDensity.compact,
                  ),
                  FilterChip(
                    label: const Text('Critical', style: TextStyle(fontSize: 11)),
                    selected: _lowFilter == _LowStockFilter.critical,
                    onSelected: (_) =>
                        setState(() => _lowFilter = _LowStockFilter.critical),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          Expanded(
            child: tab == 3
                ? lowAsync.when(
                    loading: () =>
                        const ListSkeleton(rowCount: 8, rowHeight: 72),
                    error: (_, __) => FriendlyLoadError(
                      message: 'Could not load low stock items',
                      onRetry: () =>
                          ref.invalidate(staffLowStockAlertsProvider),
                    ),
                    data: (rows) {
                      final filtered = _filterLowStock(rows);
                      if (filtered.isEmpty) {
                        return _emptyMessage(
                          _query.isEmpty
                              ? 'No low stock items'
                              : 'No items match your search',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 0),
                        itemBuilder: (ctx, i) =>
                            _StaffLowStockRow(item: filtered[i]),
                      );
                    },
                  )
                : purchasesAsync!.when(
                    loading: () =>
                        const ListSkeleton(rowCount: 10, rowHeight: 88),
                    error: (e, _) => FriendlyLoadError(
                      message: _loadErrorMessage(e),
                      onRetry: () => ref.invalidate(
                        staffTradePurchasesHistoryProvider(_period),
                      ),
                    ),
                    data: (rows) {
                      final filtered = _filterPurchases(rows);
                      if (filtered.isEmpty) {
                        return _emptyMessage(
                          _query.isEmpty
                              ? 'No purchase orders in this period'
                              : 'No orders match your search',
                        );
                      }
                      final grouped = buildGroupedPurchaseHistory(filtered);
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(
                            staffTradePurchasesHistoryProvider(_period),
                          );
                          await ref.read(
                            staffTradePurchasesHistoryProvider(_period).future,
                          );
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                          itemCount: grouped.length,
                          itemBuilder: (ctx, i) {
                            final entry = grouped[i];
                            return switch (entry) {
                              PurchaseHistoryDateHeader(:final label) =>
                                _DateHeader(label: label),
                              PurchaseHistoryPurchaseRow(:final purchase) =>
                                StaffPurchaseHistoryRow(
                                  purchase: purchase,
                                  onTap: () => context.push(
                                    '/staff/purchase-history/${purchase.id}',
                                  ),
                                ),
                            };
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMessage(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: HexaDsType.body(14, color: HexaDsColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HexaColors.brandBackground,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _StaffLowStockRow extends StatelessWidget {
  const _StaffLowStockRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? '—';
    final cur = coerceToDouble(item['current_stock']);
    final reorder = coerceToDouble(item['reorder_level']);
    final unit = item['unit']?.toString() ?? '';
    final critical = reorder > 0 && cur <= reorder * 0.5;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => context.push('/staff/low-stock'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                critical ? Icons.error_outline : Icons.warning_amber_rounded,
                color: critical ? const Color(0xFFDC2626) : HexaColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${formatStockQtyNumber(cur)} / '
                      '${formatStockQtyNumber(reorder)} $unit',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push('/staff/low-stock'),
                child: const Text('Inform owner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
