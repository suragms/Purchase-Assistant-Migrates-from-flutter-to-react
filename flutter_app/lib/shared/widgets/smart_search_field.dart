import 'package:flutter/material.dart';

import 'inline_search_field.dart';

/// Part 2: full-height draggable sheet for large suggestion sets (party + catalog).
///
/// [PartyInlineSuggestField] uses this for "See all" so inline panels stay
/// bounded and scroll-safe without duplicating sheet wiring.
Future<void> showSmartSearchResultsSheet({
  required BuildContext context,
  required String title,
  required int resultCount,
  required List<InlineSearchItem> items,
  required void Function(InlineSearchItem item) onPick,
  required Widget Function(
    BuildContext context,
    ColorScheme colorScheme,
    InlineSearchItem item,
    VoidCallback onTap,
  ) buildTile,
}) async {
  final rootNav = Navigator.of(context, rootNavigator: true);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.28,
        maxChildSize: 0.55,
        builder: (dragCtx, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetCtx).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text(
                      '$resultCount',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => rootNav.pop(),
                      icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  itemBuilder: (c, i) {
                    final it = items[i];
                    return buildTile(
                      c,
                      cs,
                      it,
                      () {
                        onPick(it);
                        rootNav.pop();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
