import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/api/hexa_api.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart'
    show homeLowStockDetailFetchEnabledProvider, lowStockDashboardMountedProvider;
import '../../../core/providers/low_stock_providers.dart';
import '../../../core/services/stock_list_pdf.dart';
import '../../../core/services/pdf_actions.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/hexa_elevated_autocomplete.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/errors/load_state_error.dart';
import 'quick_stock_action_sheet.dart';
import 'widgets/stock_update_mode_toggle.dart';
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

  /// Visual tab order (segmented control); maps to [TabController] index.
  static const _tabOrder = <LowStockTreeTab>[
    LowStockTreeTab.allLow,
    LowStockTreeTab.outOfStock,
    LowStockTreeTab.purchasedInPeriod,
    LowStockTreeTab.pendingOrder,
    LowStockTreeTab.pendingDelivery,
  ];

  late final TabController _tabs;
  Timer? _debounce;
  Timer? _loadSlowTimer;
  bool _loadTimedOut = false;
  String _search = '';
  LowStockSearchScope _searchScope = LowStockSearchScope.all;
  String? _subcategoryFilter;
  bool _exportingPdf = false;
  final _informedOwnerIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

    // Enable fetch before first build — postFrameCallback was too late (All 0 flash).
    ref.read(homeLowStockDetailFetchEnabledProvider.notifier).state = true;
    ref.read(lowStockDashboardMountedProvider.notifier).update((n) => n + 1);
    ref.read(lowStockOperationsQueryProvider.notifier).update(
          (q) => q.copyWith(perPage: HexaApi.lowStockOperationsMaxPerPage),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(lowStockOperationsPageProvider);
      ref.invalidate(lowStockOperationsSummaryProvider);
      final filter = GoRouterState.of(context).uri.queryParameters['filter'];
      final idx = _tabIndexFromFilter(filter);
      if (idx != null && idx != _tabs.index) {
        _tabs.animateTo(idx);
      }
    });
    _scheduleLoadSlowTimer();
  }

  @override
  void deactivate() {
    ref.read(lowStockDashboardMountedProvider.notifier).update(
          (n) => n > 0 ? n - 1 : 0,
        );
    super.deactivate();
  }

  void _scheduleLoadSlowTimer() {
    _loadSlowTimer?.cancel();
    _loadSlowTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (ref.read(lowStockOperationsGroupedProvider).isLoading) {
        setState(() => _loadTimedOut = true);
      }
    });
  }

  void _refreshLowStock() {
    if (_loadTimedOut && mounted) setState(() => _loadTimedOut = false);
    ref.invalidate(lowStockOperationsPageProvider);
    ref.invalidate(lowStockOperationsSummaryProvider);
    _scheduleLoadSlowTimer();
  }

  int? _tabIndexFromFilter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final tab = switch (raw.trim().toLowerCase()) {
      'all' || 'low' => LowStockTreeTab.allLow,
      'out' => LowStockTreeTab.outOfStock,
      'purchased' || 'bought' => LowStockTreeTab.purchasedInPeriod,
      'pending' => LowStockTreeTab.pendingOrder,
      'delivery' || 'pending_delivery' || 'pending-delivery' =>
        LowStockTreeTab.pendingDelivery,
      'delayed' || 'verification' || 'urgent' || 'high_impact' =>
        LowStockTreeTab.allLow,
      _ => null,
    };
    if (tab == null) return null;
    return _tabOrder.indexOf(tab);
  }

  LowStockTreeTab get _activeTab => _tabOrder[_tabs.index];

  @override
  void dispose() {
    _debounce?.cancel();
    _loadSlowTimer?.cancel();
    _tabs.dispose();
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
      setState(() => _informedOwnerIds.add(id));
      ref.invalidate(lowStockOperationsPageProvider);
      ref.invalidate(lowStockOperationsSummaryProvider);
      ref.invalidate(appNotificationsListProvider);
      ref.invalidate(notificationCenterCoordinatorProvider);
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
      ref.invalidate(lowStockOperationsPageProvider);
      ref.invalidate(lowStockOperationsSummaryProvider);
    }
  }

  Future<void> _stockUpdate(Map<String, dynamic> item) async {
    final ok = await showQuickStockActionSheet(
      context: context,
      ref: ref,
      item: item,
      initialMode: StockUpdateMode.physical,
      skipInitialRefresh: true,
    );
    if (ok && mounted) {
      ref.invalidate(lowStockOperationsPageProvider);
      ref.invalidate(lowStockOperationsSummaryProvider);
    }
  }

  Future<void> _stockUpdateSystem(Map<String, dynamic> item) async {
    final ok = await showQuickStockActionSheet(
      context: context,
      ref: ref,
      item: item,
      initialMode: StockUpdateMode.system,
      skipInitialRefresh: true,
    );
    if (ok && mounted) {
      ref.invalidate(lowStockOperationsPageProvider);
      ref.invalidate(lowStockOperationsSummaryProvider);
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
    final tab = _activeTab;
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
      final tabLabel = _tabLabel(_activeTab);
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
      final result = kIsWeb
          ? await savePdfBytes(
              buildBytes: () async => bytes,
              filename: 'harisree_low_stock.pdf',
              subject: 'Harisree low stock list',
              source: 'low_stock_pdf',
            )
          : await shareStockListPdf(
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
    final groupedAsync = ref.watch(lowStockOperationsGroupedProvider);
    ref.listen(lowStockOperationsGroupedProvider, (prev, next) {
      if (!next.isLoading) {
        _loadSlowTimer?.cancel();
        _loadSlowTimer = null;
        if (_loadTimedOut && mounted) {
          setState(() => _loadTimedOut = false);
        }
      } else if (prev != null && !prev.isLoading && next.isLoading) {
        _scheduleLoadSlowTimer();
      }
    });

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
            final suggestions = lowStockSearchSuggestions(grouped);
            return PreferredSize(
              preferredSize: Size.fromHeight(
                _subcategoryFilter != null && _subcategoryFilter!.trim().isNotEmpty
                    ? 108
                    : 88,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Autocomplete<String>(
                            optionsViewBuilder: (context, onSelected, options) {
                              return hexaElevatedAutocompleteOptions<String>(
                                context,
                                onSelected,
                                options,
                                label: (v) => v,
                              );
                            },
                            optionsBuilder: (text) {
                              final needle = text.text.trim().toLowerCase();
                              if (needle.isEmpty) return const Iterable<String>.empty();
                              return suggestions
                                  .where((s) => s.toLowerCase().contains(needle))
                                  .take(12);
                            },
                            onSelected: (v) {
                              setState(() => _search = v);
                            },
                            fieldViewBuilder:
                                (ctx, ctrl, focus, onFieldSubmitted) {
                              if (ctrl.text != _search) {
                                ctrl.text = _search;
                              }
                              return TextField(
                                controller: ctrl,
                                focusNode: focus,
                                onChanged: (v) {
                                  _debounce?.cancel();
                                  _debounce = Timer(
                                    const Duration(milliseconds: 200),
                                    () {
                                      if (!mounted) return;
                                      setState(() => _search = v.trim());
                                    },
                                  );
                                },
                                onSubmitted: (_) => onFieldSubmitted(),
                                decoration: InputDecoration(
                                  hintText: 'Search item, subcategory, supplier…',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Search & filter',
                          onPressed: () => _showFiltersSheet(subOptions),
                          icon: Icon(
                            Icons.tune_rounded,
                            color: _filtersActive
                                ? HexaColors.brandPrimary
                                : const Color(0xFF64748B),
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: _filtersActive
                                ? HexaColors.brandPrimary.withValues(alpha: 0.12)
                                : Colors.white,
                          ),
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
                  _LowStockSegmentedTabs(
                    selectedIndex: _tabs.index,
                    counts: {
                      for (final t in _tabOrder)
                        t: countLowStockForTab(grouped, t),
                    },
                    onSelected: (i) {
                      if (i != _tabs.index) _tabs.animateTo(i);
                    },
                  ),
                ],
              ),
            );
          },
          orElse: () => null,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final boundedHeight =
              constraints.maxHeight.isFinite && constraints.maxHeight > 0;
          return groupedAsync.when(
            loading: () => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loadTimedOut) ...[
                    Text(
                      'Taking longer than usual',
                      style: HexaDsType.body(14, color: HexaDsColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _refreshLowStock,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const CircularProgressIndicator(),
                ],
              ),
            ),
            error: (e, _) => FriendlyLoadError(
              message: 'Could not load low stock',
              subtitle: loadStateErrorSubtitle(e),
              onRetry: _refreshLowStock,
            ),
            data: (grouped) {
              final desktop = context.isDesktopLayout;
              final tree = TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final tab in _tabOrder)
                    LowStockCategoryTree(
                      grouped: grouped,
                      tab: tab,
                      searchQuery: _search,
                      searchScope: _searchScope,
                      subcategoryFilter: _subcategoryFilter,
                      staffMode: widget.staffMode,
                      informedOwnerIds: _informedOwnerIds,
                      onOrderNow: widget.staffMode ? null : _orderNow,
                      onNotifyOwner: widget.staffMode ? _notifyOwner : null,
                      onEditReorder: _editReorder,
                      onStockUpdate: _stockUpdate,
                      onSystemStockUpdate: _stockUpdateSystem,
                      onReceive: _receive,
                    ),
                ],
              );
              final content = RefreshIndicator(
                onRefresh: () async {
                  _refreshLowStock();
                  await ref.read(lowStockOperationsPageProvider.future);
                },
                child: desktop
                    ? HexaResponsiveCenter(
                        maxWidth: 1280,
                        padding: EdgeInsets.zero,
                        child: tree,
                      )
                    : tree,
              );
              if (!boundedHeight) return content;
              return SizedBox(
                height: constraints.maxHeight,
                child: content,
              );
            },
          );
        },
      ),
    );
  }

  bool get _filtersActive =>
      _searchScope != LowStockSearchScope.all ||
      (_subcategoryFilter != null && _subcategoryFilter!.trim().isNotEmpty);

  Future<void> _showFiltersSheet(List<String> subOptions) async {
    var scope = _searchScope;
    String? sub = _subcategoryFilter;
    await showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: HexaResponsive.adaptiveSheetMaxHeight(context) * 0.55,
        child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      children: [
                        Text(
                          'Filters',
                          style: HexaDsType.heading(16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search scope and subcategory.',
                          style: HexaDsType.body(
                            13,
                            color: HexaDsColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Search in',
                          style: HexaDsType.label(
                            12,
                            color: HexaDsColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in <(LowStockSearchScope, String)>[
                              (LowStockSearchScope.all, 'All fields'),
                              (LowStockSearchScope.category, 'Category'),
                              (LowStockSearchScope.subcategory, 'Subcategory'),
                              (LowStockSearchScope.item, 'Item name'),
                              (LowStockSearchScope.supplier, 'Supplier'),
                            ])
                              ChoiceChip(
                                label: Text(entry.$2),
                                selected: scope == entry.$1,
                                onSelected: (_) =>
                                    setSheetState(() => scope = entry.$1),
                              ),
                          ],
                        ),
                        if (subOptions.length > 1) ...[
                          const SizedBox(height: 14),
                          Text(
                            'Subcategory',
                            style: HexaDsType.label(
                              12,
                              color: HexaDsColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String?>(
                            initialValue: sub,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All subcategories'),
                              ),
                              for (final s in subOptions)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setSheetState(() => sub = v),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF065F46),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () {
                            setState(() {
                              _searchScope = scope;
                              _subcategoryFilter = sub;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Apply filters'),
                        ),
                        if (_filtersActive)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _searchScope = LowStockSearchScope.all;
                                _subcategoryFilter = null;
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear filters'),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
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

class _LowStockSegmentedTabs extends StatelessWidget {
  const _LowStockSegmentedTabs({
    required this.selectedIndex,
    required this.counts,
    required this.onSelected,
  });

  final int selectedIndex;
  final Map<LowStockTreeTab, int> counts;
  final ValueChanged<int> onSelected;

  static const _tabs = _LowStockDashboardPageState._tabOrder;

  static String _label(LowStockTreeTab t) => switch (t) {
        LowStockTreeTab.allLow => 'All',
        LowStockTreeTab.outOfStock => 'Out',
        LowStockTreeTab.purchasedInPeriod => 'Bought',
        LowStockTreeTab.pendingOrder => 'Pending',
        LowStockTreeTab.pendingDelivery => 'Delivery',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _Segment(
                label: _label(_tabs[i]),
                count: counts[_tabs[i]] ?? 0,
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFF334155);
    return Material(
      color: selected ? const Color(0xFF065F46) : const Color(0xFFF1F5F4),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
