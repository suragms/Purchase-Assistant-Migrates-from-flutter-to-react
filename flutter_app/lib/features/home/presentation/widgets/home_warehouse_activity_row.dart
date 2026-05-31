import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../purchase/presentation/purchase_home_page.dart'
    show formatPurchaseHumanDate;
import 'home_formatters.dart';

void openHomeActivityItem(BuildContext context, HomeActivityItem item) {
  final id = item.routeId;
  if (id == null || id.isEmpty) return;
  if (item.isPurchaseDelivery || item.kind == 'purchase') {
    context.push('/purchase/detail/$id');
    return;
  }
  context.push('/catalog/item/$id');
}

/// Home card preview row — compact but shows bill id when available.
class WarehouseActivityCompactRow extends StatelessWidget {
  const WarehouseActivityCompactRow({
    super.key,
    required this.item,
  });

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final icon = _activityIcon(item.kind);
    final color = _activityColor(item.kind);
    final billId = item.humanId?.trim();
    final title = billId != null && billId.isNotEmpty && item.isPurchaseDelivery
        ? billId
        : item.title;
    final subtitleParts = <String>[
      if (item.isPurchaseDelivery && item.unitsLine != null)
        item.unitsLine!
      else if (item.subtitle.isNotEmpty)
        item.subtitle,
      if (item.verifiedBy != null && item.verifiedBy!.isNotEmpty)
        'Verified by ${item.verifiedBy}'
      else if (item.actor != null && item.actor!.isNotEmpty)
        item.actor!,
      formatPurchaseHumanDate(item.at),
    ];
    final subtitle = subtitleParts.where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      dense: true,
      onTap: item.routeId != null && item.routeId!.isNotEmpty
          ? () => openHomeActivityItem(context, item)
          : null,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    );
  }
}

/// Full-page row — bill left, qty center, verifier right.
class WarehouseActivityDetailRow extends StatelessWidget {
  const WarehouseActivityDetailRow({
    super.key,
    required this.item,
  });

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final tappable = item.routeId != null && item.routeId!.isNotEmpty;
    final isDelivery = item.isPurchaseDelivery;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable ? () => openHomeActivityItem(context, item) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: isDelivery
              ? _DeliveryLayout(item: item)
              : _GenericLayout(item: item),
        ),
      ),
    );
  }
}

class _DeliveryLayout extends StatelessWidget {
  const _DeliveryLayout({required this.item});

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final bill = item.humanId?.trim();
    final leftTitle = bill != null && bill.isNotEmpty ? bill : item.title;
    final dateLabel = DateFormat('d MMM yyyy').format(item.at);
    final units = item.unitsLine ?? item.qtyChange ?? '—';
    final verifier = item.verifiedBy ?? item.actor ?? '—';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 34,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leftTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateLabel,
                style: HexaDsType.label(11, color: HexaDsColors.textMuted),
              ),
              if (item.supplierName != null &&
                  item.supplierName!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.supplierName!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 38,
          child: Column(
            children: [
              Icon(
                Icons.local_shipping_rounded,
                size: 18,
                color: HexaColors.profit.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                units,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Verified by',
                style: HexaDsType.label(10, color: HexaDsColors.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                verifier,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                  height: 1.2,
                ),
              ),
              if (item.amountInr != null && item.amountInr! > 0) ...[
                const SizedBox(height: 4),
                Text(
                  homeInr(item.amountInr!),
                  style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GenericLayout extends StatelessWidget {
  const _GenericLayout({required this.item});

  final HomeActivityItem item;

  @override
  Widget build(BuildContext context) {
    final icon = _activityIcon(item.kind);
    final color = _activityColor(item.kind);
    final meta = <String>[
      if (item.unitsLine != null && item.unitsLine!.isNotEmpty)
        item.unitsLine!
      else if (item.qtyChange != null && item.qtyChange!.isNotEmpty)
        item.qtyChange!,
      formatPurchaseHumanDate(item.at),
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (item.actor != null && item.actor!.isNotEmpty)
          Text(
            item.actor!,
            style: HexaDsType.label(11, color: HexaDsColors.textMuted),
          ),
      ],
    );
  }
}

IconData _activityIcon(String kind) {
  return switch (kind) {
    'purchase' || 'purchase_added' || 'trade_purchase' =>
      Icons.shopping_cart_rounded,
    'delivery_verified' => Icons.local_shipping_rounded,
    'stock_quick_purchase' => Icons.add_shopping_cart_rounded,
    'stock' ||
    'stock_updated' ||
    'stock_change' ||
    'stock_adjustment' ||
    'physical_count' =>
      Icons.inventory_2_rounded,
    'stock_correction' || 'correction' => Icons.build_rounded,
    'opening_stock' || 'opening_stock_set' => Icons.inventory_outlined,
    'reorder' || 'reorder_created' => Icons.shopping_bag_outlined,
    'low_stock' || 'alert' => Icons.warning_amber_rounded,
    _ => Icons.circle_outlined,
  };
}

Color _activityColor(String kind) {
  return switch (kind) {
    'purchase' || 'stock_quick_purchase' => HexaColors.brandPrimary,
    'delivery_verified' => HexaColors.profit,
    'stock' || 'physical_count' || 'stock_correction' || 'correction' =>
      const Color(0xFF0D9488),
    _ => const Color(0xFF64748B),
  };
}
