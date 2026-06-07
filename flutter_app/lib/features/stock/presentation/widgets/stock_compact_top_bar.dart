import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/navigation_ext.dart';
import 'stock_period_dropdown.dart';

/// Single-row compact stock page app bar (no TabBar).
class StockCompactTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StockCompactTopBar({
    super.key,
    required this.isStaffMode,
    required this.filterCount,
    required this.searchExpanded,
    required this.onToggleSearch,
    required this.onOpenFilters,
    this.onExportPdf,
    this.isReloading = false,
  });

  final bool isStaffMode;
  final int filterCount;
  final bool searchExpanded;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback? onExportPdf;
  final bool isReloading;

  static const double _height = 48;

  @override
  Size get preferredSize => Size.fromHeight(_height + (isReloading ? 2 : 0));

  @override
  Widget build(BuildContext context) {
    final stockBase = isStaffMode ? '/staff/stock' : '/stock';

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
      bottom: isReloading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
      actions: [
        StockPeriodDropdown(showYear: !isStaffMode, iconSize: 22),
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
              case 'changes':
                context.go('$stockBase?tab=changes');
              case 'scan':
                context.push('/barcode/scan?return=stock');
              case 'movement':
                context.go('$stockBase?tab=movement');
              case 'add':
                pushCatalogQuickAdd(context);
              case 'pdf':
                onExportPdf?.call();
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
            const PopupMenuItem(
              value: 'changes',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.history_rounded, size: 20),
                title: Text('Stock changes'),
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
}
