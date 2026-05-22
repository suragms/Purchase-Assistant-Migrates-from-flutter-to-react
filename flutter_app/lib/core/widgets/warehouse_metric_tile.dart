import 'package:flutter/material.dart';

import '../design_system/hexa_ds_tokens.dart';

/// Compact KPI tile for warehouse dashboards.
class WarehouseMetricTile extends StatelessWidget {
  const WarehouseMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.onTap,
    this.accentColor,
  });

  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    final content = Container(
      constraints: const BoxConstraints(minHeight: HexaDsWarehouse.metricTileMinHeight),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: HexaDsType.label(10, color: HexaDsColors.textMuted),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HexaDsType.body(10, color: HexaDsColors.textMuted),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}
