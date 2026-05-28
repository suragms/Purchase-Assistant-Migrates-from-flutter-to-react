import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'low_stock_bulk_export.dart';
import 'low_stock_context_panel.dart';
import 'low_stock_item_expanded.dart';

class LowStockDesktopShell extends StatefulWidget {
  const LowStockDesktopShell({
    super.key,
    required this.grouped,
    required this.staffMode,
    required this.periodDays,
    required this.selectedCategory,
    required this.onSelectedCategory,
    required this.searchController,
    required this.bulkMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onSelectItem,
    required this.selectedItem,
  });

  final Map<String, Map<String, List<Map<String, dynamic>>>> grouped;
  final bool staffMode;
  final int periodDays;
  final String? selectedCategory;
  final ValueChanged<String?> onSelectedCategory;
  final TextEditingController searchController;
  final bool bulkMode;
  final Set<String> selectedIds;
  final void Function(String itemId, bool selected) onToggleSelect;
  final ValueChanged<Map<String, dynamic>?> onSelectItem;
  final Map<String, dynamic>? selectedItem;

  @override
  State<LowStockDesktopShell> createState() => _LowStockDesktopShellState();
}

class _LowStockDesktopShellState extends State<LowStockDesktopShell> {
  @override
  Widget build(BuildContext context) {
    final categories = widget.grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    int affectedCountForCat(String cat) {
      return widget.grouped[cat]!.values.fold<int>(0, (n, list) => n + list.length);
    }

    final flat = <Map<String, dynamic>>[];
    for (final entry in widget.grouped.entries) {
      if (widget.selectedCategory != null && entry.key != widget.selectedCategory) {
        continue;
      }
      for (final items in entry.value.values) {
        flat.addAll(items);
      }
    }

    final selectedRows = flat
        .where((e) => widget.selectedIds.contains(e['id']?.toString()))
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: TextField(
                    controller: widget.searchController,
                    decoration: InputDecoration(
                      hintText: 'Search items…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                    itemCount: categories.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        final selected = widget.selectedCategory == null;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text(
                            'All categories',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                          trailing: Text(
                            '${flat.length}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          onTap: () => widget.onSelectedCategory(null),
                        );
                      }
                      final cat = categories[i - 1];
                      final count = affectedCountForCat(cat);
                      final selected = cat == widget.selectedCategory;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(
                          cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        trailing: Text(
                          '$count',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onTap: () => widget.onSelectedCategory(
                          selected ? null : cat,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.bulkMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: selectedRows.isEmpty
                            ? null
                            : () => exportLowStockSelectionCsv(
                                  context,
                                  items: selectedRows,
                                ),
                        child: const Text('Export CSV'),
                      ),
                      if (!widget.staffMode)
                        OutlinedButton(
                          onPressed: selectedRows.length != 1
                              ? null
                              : () {
                                  final id = selectedRows.first['id']?.toString();
                                  if (id == null) return;
                                  context.push('/purchase/new?catalogItemId=$id');
                                },
                          child: const Text('PO draft'),
                        ),
                      Text(
                        '${widget.selectedIds.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: flat.isEmpty
                    ? const Center(
                        child: Text(
                          'No items match',
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                        itemCount: flat.length,
                        itemBuilder: (ctx, i) {
                          final item = flat[i];
                          final id = item['id']?.toString() ?? '';
                          final isSelected = widget.selectedItem?['id']?.toString() == id;
                          return LowStockItemExpanded(
                            item: item,
                            staffMode: widget.staffMode,
                            periodDays: widget.periodDays,
                            bulkMode: widget.bulkMode,
                            selected: widget.selectedIds.contains(id),
                            highlighted: isSelected,
                            onDesktopSelect: () => widget.onSelectItem(item),
                            onSelectionChanged: (v) => widget.onToggleSelect(id, v),
                            onTapSelect: () => widget.onToggleSelect(
                              id,
                              !widget.selectedIds.contains(id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 320,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LowStockContextPanel(
                item: widget.selectedItem,
                periodDays: widget.periodDays,
                staffMode: widget.staffMode,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
