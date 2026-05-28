import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/router/post_auth_route.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/services/item_export_service.dart';
import '../../../stock/presentation/stock_quick_purchase_sheet.dart';
import '../../../stock/presentation/update_stock_sheet.dart';

class ItemQuickActionsBar extends ConsumerWidget {
  const ItemQuickActionsBar({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.itemCode,
  });

  final String itemId;
  final String itemName;
  final String? itemCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isStaff = session != null && sessionIsStaff(session);
    final isOwnerDash = session != null && sessionHasOwnerDashboard(session);

    final actions = <_ActionSpec>[
      _ActionSpec(
        label: 'Update physical',
        icon: Icons.fact_check_outlined,
        color: HexaColors.brandPrimary,
        onTap: () async {
          final row = await ref.read(stockItemDetailProvider(itemId).future);
          if (!context.mounted) return;
          await showUpdateStockSheet(
            context: context,
            ref: ref,
            itemId: itemId,
            itemName: itemName,
            stockRow: row.isEmpty ? null : row,
          );
        },
      ),
      _ActionSpec(
        label: 'Add qty',
        icon: Icons.add_shopping_cart_rounded,
        color: HexaColors.profit,
        onTap: () async {
          final item = await ref.read(stockItemDetailProvider(itemId).future);
          if (!context.mounted) return;
          if (item.isEmpty) return;
          await showStockQuickPurchaseSheet(context: context, ref: ref, item: item);
        },
      ),
      _ActionSpec(
        label: 'Ledger',
        icon: Icons.receipt_long_outlined,
        color: const Color(0xFF334155),
        onTap: () => context.push('/catalog/item/$itemId/ledger'),
      ),
      if (!isStaff)
        _ActionSpec(
          label: 'Create purchase',
          icon: Icons.playlist_add_rounded,
          color: HexaColors.brandPrimary,
          onTap: () => context.push('/purchase/new'),
        ),
      if (isOwnerDash)
        _ActionSpec(
          label: 'Print barcode',
          icon: Icons.qr_code_2_rounded,
          color: const Color(0xFF455A64),
          onTap: () => context.push('/barcode/print/${Uri.encodeComponent(itemId)}'),
        ),
      if (!isStaff)
        _ActionSpec(
          label: 'Export PDF',
          icon: Icons.picture_as_pdf_outlined,
          color: const Color(0xFF0F766E),
          onTap: () async {
            final res = await exportShareItemStatementPdf(
              ref: ref,
              catalogItemId: itemId,
              itemName: itemName,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res.message)),
            );
          },
        ),
      _ActionSpec(
        label: 'History',
        icon: Icons.history_rounded,
        color: const Color(0xFF1565C0),
        onTap: () => context.push('/stock/$itemId/history?name=${Uri.encodeComponent(itemName)}'),
      ),
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _ActionChip(spec: actions[i]),
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.spec});
  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(spec.icon, size: 18, color: spec.color),
      label: Text(
        spec.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: spec.color,
        ),
      ),
      onPressed: spec.onTap,
      backgroundColor: spec.color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

