import 'package:flutter/material.dart';
import '../../../../core/router/navigation_ext.dart';

/// Compact top bar for Opening Stock Setup.
class OpeningStockTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const OpeningStockTopBar({
    super.key,
    required this.searchExpanded,
    required this.onToggleSearch,
    required this.onOpenFilters,
    required this.onOpenProgress,
  });

  final bool searchExpanded;
  final VoidCallback onToggleSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenProgress;

  static const double _height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: _height,
      backgroundColor: const Color(0xFFF5F3EE),
      foregroundColor: const Color(0xFF1A1A1A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        tooltip: 'Back',
        onPressed: () => context.popOrGo('/stock'),
      ),
      title: const Text(
        'Opening Stock Setup',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      titleSpacing: 0,
      actions: [
        IconButton(
          icon: Icon(
            searchExpanded ? Icons.search_off_rounded : Icons.search_rounded,
            size: 22,
          ),
          tooltip: searchExpanded ? 'Hide search' : 'Search',
          onPressed: onToggleSearch,
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, size: 22),
          tooltip: 'Filters',
          onPressed: onOpenFilters,
        ),
        IconButton(
          icon: const Icon(Icons.show_chart_rounded, size: 22),
          tooltip: 'Progress',
          onPressed: onOpenProgress,
        ),
      ],
    );
  }
}

