import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/business_write_event.dart';
import '../../../core/providers/deferred_invalidation.dart';
import '../../../core/providers/item_detail_providers.dart';
import '../../../core/providers/catalog_providers.dart' show catalogItemDetailProvider;
import '../../../core/providers/stock_providers.dart'
    show stockItemActivityProvider, stockItemDetailProvider;
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/async_value_form.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/auth/session_notifier.dart' show sessionProvider;
import '../../../core/router/post_auth_route.dart' show sessionIsStaff;
import '../../stock/presentation/stock_quick_purchase_sheet.dart';
import '../../stock/presentation/update_stock_sheet.dart';
import '../../stock/presentation/widgets/stock_update_mode_toggle.dart';
import 'widgets/item_detail_header.dart';
import 'widgets/item_quick_actions_bar.dart';
import 'widgets/item_analytics_section.dart';
import 'widgets/item_price_intelligence_section.dart';
import 'widgets/item_ledger_section.dart';
import 'widgets/item_physical_verification_card.dart';
import 'widgets/item_purchase_history_section.dart';
import 'widgets/item_supplier_intelligence_section.dart';
import 'widgets/item_stock_snapshot_card.dart';
import 'widgets/item_timeline_section.dart';
import '../../stock/presentation/widgets/stock_item_history_panel.dart';

class ItemDetailPage extends ConsumerWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<BusinessWriteEvent>(businessWriteEventProvider, (prev, next) {
      if (next.revision <= (prev?.revision ?? -1)) return;
      if (next.kind == 'stock_patch') return;
      final purchaseOrStock = next.kind == 'purchase' ||
          next.kind == 'stock';
      if (purchaseOrStock &&
          (next.affectsItem(itemId) || next.isGlobal)) {
        deferInvalidate(ref, itemDetailBundleProvider(itemId));
        deferInvalidate(ref, tradePurchasesForItemProvider(itemId));
        deferInvalidate(ref, stockItemDetailProvider(itemId));
      }
    });

    final bundleAsync = ref.watch(itemDetailBundleProvider(itemId));
    final cachedBundle = bundleAsync.valueOrNull;
    final gutter = HexaResponsive.pageGutter(context, operational: true);
    final desktop = HexaBreakpoints.isDesktop(context);

    Widget buildDetail(ItemDetailBundle bundle, {bool refreshing = false}) {
      final item = bundle.catalogItem;
      final stock = bundle.stockDetail;
      final name = (item['name']?.toString() ?? '').trim();
      final code = (item['item_code']?.toString() ?? '').trim();
      final cat = (stock['category_name']?.toString() ??
              item['category_name']?.toString() ??
              '')
          .trim();
      final sub = (stock['subcategory_name']?.toString() ??
              item['type_name']?.toString() ??
              '')
          .trim();
      final categoryLabel = [cat, sub].where((s) => s.isNotEmpty).join(' · ');

      Future<void> doRefresh() async {
        ref.invalidate(itemDetailBundleProvider(itemId));
      }

      final Widget scrollBody;
      if (desktop) {
        scrollBody = RefreshIndicator(
          onRefresh: doRefresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 16),
                    child: HexaResponsiveCenter(
                      maxWidth: HexaResponsive.maxContentWidth,
                      padding: EdgeInsets.zero,
                      child: _DesktopItemLayout(
                        itemId: itemId,
                        name: name.isNotEmpty
                            ? name
                            : (code.isNotEmpty ? code : 'Item'),
                        code: code.isNotEmpty ? code : null,
                        categoryLabel: categoryLabel,
                        onMore: () => _showMore(context, ref, item),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      } else {
        scrollBody = _ItemDetailMobileScroll(
          itemId: itemId,
          name: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Item'),
          code: code.isNotEmpty ? code : null,
          categoryLabel: categoryLabel,
          gutter: gutter,
          onRefresh: doRefresh,
          onMore: () => _showMore(context, ref, item),
        );
      }

      Widget content = SizedBox.expand(child: scrollBody);

      if (!refreshing) return content;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          formReloadBanner(),
          Expanded(child: content),
        ],
      );
    }

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: bundleAsync.whenForm(
          initialLoading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) {
            if (cachedBundle != null && cachedBundle.hasAnyData) {
              return buildDetail(
                cachedBundle,
                refreshing: bundleAsync.isLoading,
              );
            }
            return FriendlyLoadError(
              message: 'Could not load item. Tap to retry.',
              onRetry: () {
                ref.invalidate(catalogItemDetailProvider(itemId));
                ref.invalidate(stockItemDetailProvider(itemId));
                ref.invalidate(stockItemActivityProvider(itemId));
                ref.invalidate(itemDetailBundleProvider(itemId));
              },
            );
          },
          data: (bundle) {
            if (bundle.allSectionsFailed) {
              return FriendlyLoadError(
                message: 'Could not load item. Tap to retry.',
                onRetry: () {
                  ref.invalidate(catalogItemDetailProvider(itemId));
                  ref.invalidate(stockItemDetailProvider(itemId));
                  ref.invalidate(stockItemActivityProvider(itemId));
                  ref.invalidate(itemDetailBundleProvider(itemId));
                },
              );
            }
            return buildDetail(
              bundle,
              refreshing: bundleAsync.isLoading && cachedBundle != null,
            );
          },
        ),
      ),
      bottomNavigationBar: bundleAsync.hasValue && !bundleAsync.hasError && !desktop
          ? _ItemStickyActions(
              itemId: itemId,
              itemName: (bundleAsync.valueOrNull?.catalogItem['name']?.toString() ?? '').trim(),
            )
          : null,
    );
  }

  Future<void> _showMore(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    final itemName = (item['name']?.toString() ?? 'Item').trim();
    final v = await showHexaBottomSheet<String>(
      context: context,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Ledger & statement'),
            onTap: () => Navigator.pop(context, 'ledger'),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: const Text('Purchase history'),
            onTap: () => Navigator.pop(context, 'history'),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Activity'),
            onTap: () => Navigator.pop(context, 'activity'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy item name'),
            subtitle: Text(itemName),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    switch (v) {
      case 'ledger':
        context.push('/catalog/item/$itemId/ledger');
      case 'history':
        context.push('/catalog/item/$itemId/purchase-history');
      case 'activity':
        context.push('/stock/intelligence/$itemId');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: itemName));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied')),
        );
    }
  }
}

class _ItemStickyActions extends ConsumerWidget {
  const _ItemStickyActions({required this.itemId, required this.itemName});

  final String itemId;
  final String itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final isStaff = sessionIsStaff(session);
    final name = itemName.trim().isNotEmpty ? itemName.trim() : 'Item';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final row = ref.read(itemDetailStockProvider(itemId)).valueOrNull;
                  if (!context.mounted) return;
                  await showUpdateStockSheet(
                    context: context,
                    ref: ref,
                    itemId: itemId,
                    itemName: name,
                    stockRow: row == null || row.isEmpty ? null : row,
                    initialMode: StockUpdateMode.physical,
                  );
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Physical count'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final row = ref.read(itemDetailStockProvider(itemId)).valueOrNull;
                  if (!context.mounted) return;
                  await showUpdateStockSheet(
                    context: context,
                    ref: ref,
                    itemId: itemId,
                    itemName: name,
                    stockRow: row == null || row.isEmpty ? null : row,
                    initialMode: StockUpdateMode.system,
                  );
                },
                icon: const Icon(Icons.memory_outlined),
                label: const Text('System stock'),
              ),
            ),
            if (!isStaff) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final item =
                        ref.read(itemDetailStockProvider(itemId)).valueOrNull;
                    if (!context.mounted) return;
                    if (item == null || item.isEmpty) return;
                    await showStockQuickPurchaseSheet(
                      context: context,
                      ref: ref,
                      item: item,
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Add qty'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopItemLayout extends ConsumerWidget {
  const _DesktopItemLayout({
    required this.itemId,
    required this.name,
    required this.code,
    required this.categoryLabel,
    required this.onMore,
  });

  final String itemId;
  final String name;
  final String? code;
  final String categoryLabel;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final tab = _ItemDetailMobileScrollState._tabQuery(context);
    final initialIndex = switch (tab) {
      'purchases' || 'history' || 'purchase' => 1,
      'analytics' || 'price' => 2,
      _ => 0,
    };
    if (isStaff) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ItemDetailHeader(
              itemName: name,
              categoryLabel: categoryLabel,
              snapshot: null,
              onEdit: () => context.push('/catalog/item/$itemId/edit'),
              onMore: onMore,
            ),
            const SizedBox(height: 8),
            ItemStockSnapshotCard(itemId: itemId),
            const SizedBox(height: 8),
            ItemPhysicalVerificationCard(itemId: itemId),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ItemDetailHeader(
            itemName: name,
            categoryLabel: categoryLabel,
            snapshot: null,
            onEdit: () => context.push('/catalog/item/$itemId/edit'),
            onMore: onMore,
          ),
          const SizedBox(height: 8),
          ItemStockSnapshotCard(itemId: itemId),
          const SizedBox(height: 8),
          ItemQuickActionsBar(
            itemId: itemId,
            itemName: name,
            itemCode: code,
          ),
          const SizedBox(height: 8),
          ItemPhysicalVerificationCard(itemId: itemId),
          const SizedBox(height: 8),
          ItemSupplierIntelligenceSection(itemId: itemId, itemName: name),
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Ledger'),
              Tab(text: 'Purchases'),
              Tab(text: 'Analytics'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ItemLedgerSection(itemId: itemId),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ItemPurchaseHistorySection(
                    itemId: itemId,
                    itemName: name,
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ItemAnalyticsSection(
                            itemId: itemId,
                            loadIntelligence: true,
                          ),
                        ),
                      ),
                      if (name.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ItemPriceIntelligenceSection(itemName: name),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemDetailMobileScroll extends ConsumerStatefulWidget {
  const _ItemDetailMobileScroll({
    required this.itemId,
    required this.name,
    required this.code,
    required this.categoryLabel,
    required this.gutter,
    required this.onRefresh,
    required this.onMore,
  });

  final String itemId;
  final String name;
  final String? code;
  final String categoryLabel;
  final double gutter;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore;

  @override
  ConsumerState<_ItemDetailMobileScroll> createState() =>
      _ItemDetailMobileScrollState();
}

class _ItemDetailMobileScrollState extends ConsumerState<_ItemDetailMobileScroll>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<int> _loadedTabIndexes = {0};

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    final isStaff =
        session != null && sessionIsStaff(session);
    final tabCount = isStaff ? 2 : 3;
    final initial = _initialTabIndex(isStaff).clamp(0, tabCount - 1);
    _loadedTabIndexes.add(initial);
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: initial,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final idx = _tabController.index;
    if (_loadedTabIndexes.add(idx) && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _tabReady(int index) => _loadedTabIndexes.contains(index);

  int _initialTabIndex(bool isStaff) {
    final tab = _tabQuery(context);
    if (isStaff) {
      if (tab == 'history' ||
          tab == 'stock-history' ||
          tab == 'activity' ||
          tab == 'ledger') {
        return 1;
      }
      return 0;
    }
    if (tab == 'purchases' ||
        tab == 'purchase' ||
        tab == 'ledger' ||
        tab == 'analytics' ||
        tab == 'price') {
      return 1;
    }
    if (tab == 'history' || tab == 'stock-history') return 2;
    return 0;
  }

  static String? _tabQuery(BuildContext context) {
    return GoRouter.maybeOf(context)
        ?.state
        .uri
        .queryParameters['tab']
        ?.toLowerCase();
  }

  Widget _paddedSection(Widget child) {
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.gutter, 8, widget.gutter, 8),
      child: HexaResponsiveCenter(
        maxWidth: HexaResponsive.maxContentWidth,
        padding: EdgeInsets.zero,
        child: child,
      ),
    );
  }

  Widget _scrollTab(Widget child) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: child,
    );
  }

  Widget _overviewTab(bool isStaff) {
    if (!_tabReady(0)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return _scrollTab(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _paddedSection(ItemPhysicalVerificationCard(itemId: widget.itemId)),
          if (!isStaff) ...[
            _paddedSection(
              ItemAnalyticsSection(
                itemId: widget.itemId,
                loadIntelligence: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _purchasesTab() {
    if (!_tabReady(1)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return _scrollTab(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: [
        _paddedSection(ItemLedgerSection(itemId: widget.itemId)),
        _paddedSection(
          ItemPurchaseHistorySection(
            itemId: widget.itemId,
            itemName: widget.name,
          ),
        ),
        _paddedSection(
          ItemSupplierIntelligenceSection(
            itemId: widget.itemId,
            itemName: widget.name,
          ),
        ),
        if (widget.name.isNotEmpty)
          _paddedSection(
            ItemPriceIntelligenceSection(itemName: widget.name),
          ),
      ],
      ),
    );
  }

  Widget _activityTab(int tabIndex) {
    if (!_tabReady(tabIndex)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return _scrollTab(
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: [
        _paddedSection(
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Stock change history',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 360,
                    child: StockItemHistoryPanel(
                      itemId: widget.itemId,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _paddedSection(ItemTimelineSection(itemId: widget.itemId)),
      ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(widget.gutter, 8, widget.gutter, 0),
            child: HexaResponsiveCenter(
              maxWidth: HexaResponsive.maxContentWidth,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ItemDetailHeader(
                    itemName: widget.name,
                    categoryLabel: widget.categoryLabel,
                    snapshot: null,
                    onEdit: () =>
                        context.push('/catalog/item/${widget.itemId}/edit'),
                    onMore: widget.onMore,
                  ),
                  const SizedBox(height: 8),
                  ItemStockSnapshotCard(itemId: widget.itemId),
                  const SizedBox(height: 8),
                  ItemQuickActionsBar(
                    itemId: widget.itemId,
                    itemName: widget.name,
                    itemCode: widget.code,
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: HexaColors.brandBackground,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              onTap: (index) {
                if (_loadedTabIndexes.add(index) && mounted) {
                  setState(() {});
                }
              },
              tabs: isStaff
                  ? const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Activity'),
                    ]
                  : const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Purchases'),
                      Tab(text: 'Activity'),
                    ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: isStaff
                  ? [
                      _overviewTab(isStaff),
                      _activityTab(1),
                    ]
                  : [
                      _overviewTab(isStaff),
                      _purchasesTab(),
                      _activityTab(2),
                    ],
            ),
          ),
        ],
    );
  }
}
