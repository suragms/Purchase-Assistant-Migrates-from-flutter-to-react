import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/services/stock_list_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'quick_stock_action_sheet.dart';
import 'widgets/low_stock_bulk_export.dart';
import 'widgets/low_stock_category_tree.dart';
import 'widgets/reorder_level_sheet.dart';

/// Unified low-stock dashboard for owner and staff (category tree + tabs).
class LowStockDashboardPage extends ConsumerStatefulWidget {
  const LowStockDashboardPage({super.key, required this.staffMode});

  final bool staffMode;

  @override
  ConsumerState<LowStockDashboardPage> createState() =>
      _LowStockDashboardPageState();
}

class _LowStockDashboardPageState extends ConsumerState<LowStockDashboardPage>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 5;

  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  LowStockSearchScope _searchScope = LowStockSearchScope.all;
  String? _subcategoryFilter;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final filter = GoRouterState.of(context).uri.queryParameters['filter'];
      final idx = _tabIndexFromFilter(filter);
      if (idx != null && idx != _tabs.index) {
        _tabs.animateTo(idx);
      }
    });
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q == _search) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _search = q);
    });
  }

  int? _tabIndexFromFilter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return switch (raw.trim().toLowerCase()) {
      'all' || 'low' => 0,
      'pending' => 1,
      'out' => 2,
      'purchased' => 3,
      'delivery' || 'pending_delivery' || 'pending-delivery' => 4,
      'delayed' || 'verification' || 'urgent' || 'high_impact' => 0,
      _ => null,
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _notifyOwner(Map<String, dynamic> item) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Item';
    if (id.isEmpty) return;
    try {
      await ref.read(hexaApiProvider).notifyOwnerStockItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Owner notified about $name')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _editReorder(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = item['name']?.toString() ?? 'Item';
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'bag';
    final ok = await showReorderLevelSheet(
      context: context,
      ref: ref,
      itemId: id,
      itemName: name,
      unit: unit,
      currentReorder: reorderLevelFromStockRow(item),
    );
    if (ok && mounted) {
      ref.invalidate(lowStockByCategoryProvider);
    }
  }

  Future<void> _stockUpdate(Map<String, dynamic> item) async {
    final ok = await showQuickStockActionSheet(
      context: context,
      ref: ref,
      item: item,
    );
    if (ok && mounted) {
      ref.invalidate(lowStockByCategoryProvider);
    }
  }

  void _orderNow(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      context.push('/purchase/new?itemId=$id');
    } else {
      context.push('/purchase/new');
    }
  }

  void _receive(Map<String, dynamic> item) {
    final hid = item['last_purchase_human_id']?.toString();
    if (widget.staffMode) {
      if (hid != null && hid.isNotEmpty) {
        context.push('/staff/receive/$hid');
      } else {
        context.push('/staff/receive');
      }
    } else {
      context.push('/purchase');
    }
  }

  List<Map<String, dynamic>> _filteredFlatItems(
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  ) {
    final tab = LowStockTreeTab.values[_tabs.index];
    final filtered = filterLowStockGrouped(
      grouped: grouped,
      tab: tab,
      searchQuery: _search,
      searchScope: _searchScope,
      subcategoryFilter: _subcategoryFilter,
    );
    return flattenLowStockGrouped(filtered);
  }

  Future<void> _exportPdf(
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  ) async {
    if (_exportingPdf) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final items = _filteredFlatItems(grouped);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in this view to export')),
      );
      return;
    }
    setState(() => _exportingPdf = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing low-stock PDF…')),
        );
      }
      final tabLabel = _tabLabel(LowStockTreeTab.values[_tabs.index]);
      final filterParts = <String>[tabLabel];
      if (_search.isNotEmpty) filterParts.add('Search: $_search');
      if (_subcategoryFilter != null && _subcategoryFilter!.isNotEmpty) {
        filterParts.add('Sub: $_subcategoryFilter');
      }
      final bytes = await buildStockListPdf(
        businessName: session.primaryBusiness.effectiveDisplayTitle,
        rows: items.take(500).toList(),
        filterSummary: 'Low stock · ${filterParts.join(' · ')}',
      );
      final result = await shareStockListPdf(
        bytes: bytes,
        filename: 'harisree_low_stock.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create PDF. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportCsv(
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
  ) async {
    await exportLowStockSelectionCsv(
      context,
      items: _filteredFlatItems(grouped),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedAsync = ref.watch(lowStockByCategoryProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Low stock'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: groupedAsync.maybeWhen(
          data: (grouped) => [
            IconButton(
              tooltip: 'Download PDF',
              onPressed: _exportingPdf ? null : () => _exportPdf(grouped),
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'Copy CSV',
              onPressed: () => _exportCsv(grouped),
              icon: const Icon(Icons.table_chart_outlined),
            ),
          ],
          orElse: () => null,
        ),
        bottom: groupedAsync.maybeWhen(
          data: (grouped) {
            final n = countLowStockForTab(grouped, LowStockTreeTab.allLow);
            final subOptions = lowStockSubcategoryOptions(grouped);
            return PreferredSize(
              preferredSize: Size.fromHeight(subOptions.length > 1 ? 118 : 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search items, category…',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              prefixIcon: const Icon(Icons.search, size: 20),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _scopeIcon(
                          icon: Icons.layers_outlined,
                          scope: LowStockSearchScope.all,
                          tooltip: 'Search all',
                        ),
                        _scopeIcon(
                          icon: Icons.category_outlined,
                          scope: LowStockSearchScope.category,
                          tooltip: 'Category',
                        ),
                        _scopeIcon(
                          icon: Icons.account_tree_outlined,
                          scope: LowStockSearchScope.subcategory,
                          tooltip: 'Subcategory',
                        ),
                        _scopeIcon(
                          icon: Icons.inventory_2_outlined,
                          scope: LowStockSearchScope.item,
                          tooltip: 'Item name',
                        ),
                        PopupMenuButton<String?>(
                          tooltip: 'Subcategory filter',
                          icon: Icon(
                            Icons.filter_alt_outlined,
                            color: _subcategoryFilter != null
                                ? HexaColors.brandPrimary
                                : null,
                          ),
                          onSelected: (v) =>
                              setState(() => _subcategoryFilter = v),
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: null,
                              child: Text('All subcategories'),
                            ),
                            for (final sub in subOptions)
                              PopupMenuItem(
                                value: sub,
                                child: Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_subcategoryFilter != null &&
                      _subcategoryFilter!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text(
                            _subcategoryFilter!,
                            style: const TextStyle(fontSize: 11),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _subcategoryFilter = null),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                    child: Text(
                      '$n need attention · Period follows Home',
                      style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: [
                      _tabWithBadge(
                        icon: Icons.warning_amber_rounded,
                        label: 'All',
                        count: n,
                      ),
                      _tabWithBadge(
                        icon: Icons.schedule_rounded,
                        label: 'Pending',
                        count: countLowStockForTab(
                          grouped,
                          LowStockTreeTab.pendingOrder,
                        ),
                      ),
                      _tabWithBadge(
                        icon: Icons.remove_shopping_cart_outlined,
                        label: 'Out',
                        count: countLowStockForTab(
                          grouped,
                          LowStockTreeTab.outOfStock,
                        ),
                      ),
                      _tabWithBadge(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Bought',
                        count: countLowStockForTab(
                          grouped,
                          LowStockTreeTab.purchasedInPeriod,
                        ),
                      ),
                      _tabWithBadge(
                        icon: Icons.local_shipping_outlined,
                        label: 'Delivery',
                        count: countLowStockForTab(
                          grouped,
                          LowStockTreeTab.pendingDelivery,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          orElse: () => null,
        ),
      ),
      body: groupedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load low stock',
          onRetry: () => ref.invalidate(lowStockByCategoryProvider),
        ),
        data: (grouped) {
          final desktop = context.isDesktopLayout;
          final tree = TabBarView(
            controller: _tabs,
            children: [
              for (final tab in LowStockTreeTab.values)
                LowStockCategoryTree(
                  grouped: grouped,
                  tab: tab,
                  searchQuery: _search,
                  searchScope: _searchScope,
                  subcategoryFilter: _subcategoryFilter,
                  staffMode: widget.staffMode,
                  onOrderNow: widget.staffMode ? null : _orderNow,
                  onNotifyOwner: widget.staffMode ? _notifyOwner : null,
                  onEditReorder: _editReorder,
                  onStockUpdate: _stockUpdate,
                  onReceive: _receive,
                ),
            ],
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(lowStockByCategoryProvider);
              await ref.read(lowStockByCategoryProvider.future);
            },
            child: desktop
                ? HexaResponsiveCenter(
                    maxWidth: 1280,
                    padding: EdgeInsets.zero,
                    child: tree,
                  )
                : tree,
          );
        },
      ),
    );
  }

  Widget _scopeIcon({
    required IconData icon,
    required LowStockSearchScope scope,
    required String tooltip,
  }) {
    final active = _searchScope == scope;
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: tooltip,
      onPressed: () => setState(() => _searchScope = scope),
      icon: Icon(
        icon,
        size: 20,
        color: active ? HexaColors.brandPrimary : const Color(0xFF64748B),
      ),
      style: IconButton.styleFrom(
        backgroundColor:
            active ? HexaColors.brandPrimary.withValues(alpha: 0.12) : null,
      ),
    );
  }

  Tab _tabWithBadge({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Tab(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 999 ? '999+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _tabLabel(LowStockTreeTab tab) => switch (tab) {
        LowStockTreeTab.allLow => 'All low',
        LowStockTreeTab.pendingOrder => 'Pending order',
        LowStockTreeTab.outOfStock => 'Out of stock',
        LowStockTreeTab.purchasedInPeriod => 'Purchased in period',
        LowStockTreeTab.pendingDelivery => 'Pending delivery',
      };
}
