import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/home_dashboard_provider.dart';

/// Compact warehouse stock top bar: Back, Stock, Period, Filters, Search, More.
class StockOperationalTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StockOperationalTopBar({
    super.key,
    required this.isStaffMode,
    required this.filterCount,
    required this.searchExpanded,
    required this.onToggleSearch,
    required this.onOpenFilters,
    required this.currentPeriod,
    required this.onOpenPeriod,
    this.onOpenMovement,
    this.onExportPdf,
    this.onExportExcel,
    this.isReloading = false,
    this.tabController,
  });

  final bool isStaffMode;
  final int filterCount;
  final bool searchExpanded;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenFilters;
  final HomePeriod currentPeriod;
  final VoidCallback onOpenPeriod;
  final VoidCallback? onOpenMovement;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportExcel;
  final bool isReloading;
  final TabController? tabController;

  static const double _height = 48;
  static const double _tabBarHeight = 40;

  @override
  Size get preferredSize => Size.fromHeight(
        _height +
            (tabController != null ? _tabBarHeight : 0) +
            (isReloading ? 2 : 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: _height,
      backgroundColor: const Color(0xFFF5F3EE),
      foregroundColor: const Color(0xFF1A1A1A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        tooltip: 'Home',
        onPressed: () => context.go(isStaffMode ? '/staff/home' : '/home'),
      ),
      title: const Text(
        'Stock',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(
          (isReloading ? 2 : 0) + (tabController != null ? _tabBarHeight : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReloading)
              const LinearProgressIndicator(minHeight: 2),
            if (tabController != null)
              TabBar(
                controller: tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Stock'),
                  Tab(text: 'Activity'),
                ],
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Badge(
            isLabelVisible: currentPeriod != HomePeriod.allTime,
            label: Text(_periodLabel(currentPeriod)),
            child: const Icon(Icons.date_range_rounded, size: 22),
          ),
          tooltip: 'Filter by period',
          onPressed: onOpenPeriod,
        ),
        IconButton(
          icon: Badge(
            isLabelVisible: filterCount > 0,
            label: Text('$filterCount'),
            child: const Icon(Icons.tune_rounded, size: 22),
          ),
          tooltip: 'Filters',
          onPressed: onOpenFilters,
        ),
        IconButton(
          icon: Icon(
            searchExpanded ? Icons.search_off_rounded : Icons.search_rounded,
            size: 22,
          ),
          tooltip: searchExpanded ? 'Hide search' : 'Search',
          onPressed: onToggleSearch,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 22),
          onSelected: (v) {
            switch (v) {
              case 'scan':
                context.push('/barcode/scan?return=stock');
              case 'movement':
                onOpenMovement?.call();
              case 'add':
                context.push('/catalog/quick-add');
              case 'pdf':
                onExportPdf?.call();
              case 'excel':
                onExportExcel?.call();
            }
          },
          itemBuilder: (ctx) => [
            if (onExportPdf != null)
              const PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.picture_as_pdf_outlined, size: 20),
                  title: Text('Download stock PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (onExportExcel != null)
              const PopupMenuItem(
                value: 'excel',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.table_chart_outlined, size: 20),
                  title: Text('Download stock Excel'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'scan',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.qr_code_scanner_rounded, size: 20),
                title: Text('Scan'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (!isStaffMode) ...[
              const PopupMenuItem(
                value: 'movement',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.swap_vert_rounded, size: 20),
                  title: Text('Stock movement'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'add',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.add_rounded, size: 20),
                  title: Text('Add item'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _periodLabel(HomePeriod p) => switch (p) {
        HomePeriod.today => 'Today',
        HomePeriod.week => 'Week',
        HomePeriod.month => 'Month',
        HomePeriod.year => 'Year',
        HomePeriod.allTime => 'All',
        HomePeriod.custom => 'Custom',
      };
}
