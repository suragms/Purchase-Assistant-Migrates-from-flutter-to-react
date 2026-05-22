import 'package:flutter/material.dart';

import '../design_system/hexa_ds_tokens.dart';

/// Industrial-density card shell for warehouse surfaces.
class WarehouseCompactCard extends StatelessWidget {
  const WarehouseCompactCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.border,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = Padding(
      padding: padding ?? HexaDsWarehouse.cardInsets,
      child: child,
    );
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? cs.surface,
        borderRadius: HexaDsWarehouse.card,
        border: border ?? Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: HexaDsShadows.card,
      ),
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: HexaDsWarehouse.card,
                child: body,
              ),
            ),
    );
    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
