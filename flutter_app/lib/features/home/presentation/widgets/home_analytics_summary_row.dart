import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import 'home_analytics_helpers.dart';
import 'home_formatters.dart';

/// Top row inside analytics card: on-hand units + stock value (backend SSOT).
class HomeAnalyticsSummaryRow extends StatelessWidget {
  const HomeAnalyticsSummaryRow({
    super.key,
    required this.inventory,
    this.loading = false,
  });

  final HomeInventorySummary inventory;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock on hand',
                style: HexaDsType.labelCaps(context).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                loading ? '…' : inventoryUnitsLine(inventory),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HexaDsType.bodySm(context).copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Value',
              style: HexaDsType.labelCaps(context).copyWith(fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              loading ? '…' : homeInr(inventory.totalValueInr),
              style: HexaDsType.heading(16, color: HexaDsColors.textPrimary),
            ),
          ],
        ),
      ],
    );
  }
}
