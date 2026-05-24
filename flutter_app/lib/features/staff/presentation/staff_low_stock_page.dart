import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../stock/presentation/widgets/low_stock_category_tree.dart';
import '../../stock/presentation/widgets/reorder_level_sheet.dart';

/// Staff low-stock dashboard — category tree, notify owner (no purchase create).
class StaffLowStockPage extends ConsumerStatefulWidget {
  const StaffLowStockPage({super.key});

  @override
  ConsumerState<StaffLowStockPage> createState() => _StaffLowStockPageState();
}

class _StaffLowStockPageState extends ConsumerState<StaffLowStockPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _search && mounted) setState(() => _search = q);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _countForTab(
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped,
    LowStockTreeTab tab,
  ) {
    var n = 0;
    for (final subMap in grouped.values) {
      for (final items in subMap.values) {
        for (final item in items) {
          final status = (item['stock_status']?.toString() ?? '').toLowerCase();
          final stock = coerceToDouble(item['current_stock']);
          final pending = item['has_pending_order'] == true;
          final ok = switch (tab) {
            LowStockTreeTab.pendingOrder => pending,
            LowStockTreeTab.outOfStock => stock <= 0 || status == 'out',
            LowStockTreeTab.allLow =>
              status == 'low' || status == 'critical',
          };
          if (ok) n++;
        }
      }
    }
    return n;
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
        SnackBar(
          content: Text('Owner notified about $name'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyApiError(e)),
          duration: const Duration(seconds: 6),
        ),
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

  @override
  Widget build(BuildContext context) {
    final groupedAsync = ref.watch(lowStockByCategoryProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Low stock'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        bottom: groupedAsync.maybeWhen(
          data: (grouped) {
            final n = _countForTab(grouped, LowStockTreeTab.allLow);
            return PreferredSize(
              preferredSize: const Size.fromHeight(96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      '$n items need attention',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search items…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'All low ($n)'),
                      Tab(
                        text:
                            'Pending (${_countForTab(grouped, LowStockTreeTab.pendingOrder)})',
                      ),
                      Tab(
                        text:
                            'Out (${_countForTab(grouped, LowStockTreeTab.outOfStock)})',
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
        data: (grouped) => TabBarView(
          controller: _tabs,
          children: [
            LowStockCategoryTree(
              grouped: grouped,
              tab: LowStockTreeTab.allLow,
              searchQuery: _search,
              staffMode: true,
              onNotifyOwner: _notifyOwner,
              onEditReorder: _editReorder,
            ),
            LowStockCategoryTree(
              grouped: grouped,
              tab: LowStockTreeTab.pendingOrder,
              searchQuery: _search,
              staffMode: true,
              onNotifyOwner: _notifyOwner,
              onEditReorder: _editReorder,
            ),
            LowStockCategoryTree(
              grouped: grouped,
              tab: LowStockTreeTab.outOfStock,
              searchQuery: _search,
              staffMode: true,
              onNotifyOwner: _notifyOwner,
              onEditReorder: _editReorder,
            ),
          ],
        ),
      ),
    );
  }
}
