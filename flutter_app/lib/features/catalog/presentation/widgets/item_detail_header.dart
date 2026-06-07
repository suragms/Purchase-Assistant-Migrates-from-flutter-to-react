import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/router/navigation_ext.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../domain/item_stock_snapshot.dart';

class ItemDetailHeader extends ConsumerWidget {
  const ItemDetailHeader({
    super.key,
    required this.itemName,
    required this.categoryLabel,
    required this.snapshot,
    required this.onEdit,
    required this.onMore,
  });

  final String itemName;
  final String categoryLabel;
  final ItemStockSnapshot? snapshot;
  final VoidCallback onEdit;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final title = itemName.trim().isNotEmpty ? itemName.trim() : 'Item';
    final sub = categoryLabel.trim();

    final snap = snapshot;
    final chipLabel = snap?.statusChipLabel();
    final chipColor = snap?.statusColor() ?? cs.outlineVariant;

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => context.popOrGo('/catalog'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HexaDsType.heading(
                          15,
                          color: HexaColors.textBody,
                        ),
                      ),
                    ),
                    if (chipLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: chipColor.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Text(
                          chipLabel,
                          style: HexaDsType.labelCaps(context).copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: chipColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.bodySm(context).copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            child: const Text('Edit'),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }
}

