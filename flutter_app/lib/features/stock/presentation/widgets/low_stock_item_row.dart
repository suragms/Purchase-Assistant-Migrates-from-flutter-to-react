import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/dashboard_role.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/services/item_export_service.dart';
import '../../../../core/providers/low_stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';

import '../quick_stock_action_sheet.dart';
import 'reorder_level_sheet.dart';
import 'stock_row_metrics.dart';
import '../../../catalog/domain/item_stock_snapshot.dart';
import 'low_stock_approval_sheet.dart';

class LowStockItemRow extends ConsumerWidget {
  const LowStockItemRow({
    super.key,
    required this.item,
    required this.staffMode,
    required this.periodDays,
    this.highlightSelected = false,
  });

  final Map<String, dynamic> item;
  final bool staffMode;
  final int periodDays;
  final bool highlightSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ItemStockSnapshot.fromStockListRow(item);
    final unit = snap.unitLabel;
    final status = snap.status;
    final statusText = snap.statusChipLabel();

    final pendingDays = item['pending_order_days'] is num
        ? (item['pending_order_days'] as num).toInt()
        : null;
    final hasPending = item['has_pending_order'] == true;

    final diffAbs = snap.diffQty.abs();
    final isDisputed = diffAbs > 0.001;
    final isDelayed = hasPending && (pendingDays ?? 0) >= 7;

    final urgency = (() {
      if (status == ItemStockStatus.outOfStock || status == ItemStockStatus.negative) {
        return 'OUT URGENT';
      }
      if (isDelayed) return 'DELAYED';
      if (isDisputed) return 'DISPUTED';
      if (snap.needsVerification) return 'VERIFICATION';
      if (status == ItemStockStatus.lowStock) return 'LOW';
      return 'NORMAL';
    })();

    final unitDisplay = unit.isNotEmpty ? unit : 'PIECE';
    final usage = coerceToDouble(item['period_usage_qty']);
    final usagePerDay = usage / (periodDays > 0 ? periodDays : 1);

    final etaLabel = hasPending
        ? (pendingDays != null ? '${pendingDays}d ETA' : 'ETA pending')
        : '—';

    final apiStage = item['lifecycle_stage']?.toString();
    final lifecycleStage = apiStage != null && apiStage.isNotEmpty
        ? apiStage.toUpperCase()
        : (() {
            if (isDelayed) return 'DELAYED';
            if (hasPending) return 'ORDERED';
            if (isDisputed) return 'DISPUTED';
            if (snap.needsVerification) return 'VERIFICATION';
            if (status == ItemStockStatus.outOfStock ||
                status == ItemStockStatus.negative) {
              return 'OUT';
            }
            if (status == ItemStockStatus.lowStock) return 'LOW';
            return 'ATTENTION';
          })();

    final updatedAtRaw = item['last_stock_updated_at']?.toString();
    final updatedAt = updatedAtRaw == null
        ? null
        : DateTime.tryParse(updatedAtRaw)?.toLocal();
    final updatedBy = item['last_stock_updated_by']?.toString().trim();

    final supplier = item['supplier_name']?.toString().trim();
    final deliveryCue = StockRowMetrics.inlineDeliveryCue(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: highlightSelected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlightSelected
              ? Theme.of(context).colorScheme.primary
              : snap.statusColor().withValues(alpha: 0.25),
          width: highlightSelected ? 1.5 : 1,
        ),
      ),
      elevation: 0,
      child: InkWell(
        onTap: () {
          final id = item['id']?.toString();
          if (id == null || id.isEmpty) return;
          context.push('/catalog/item/$id');
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item['name']?.toString() ?? 'Item').trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HexaDsType.heading(13, color: HexaColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['subcategory_name']?.toString().trim().isNotEmpty ==
                                  true
                              ? item['subcategory_name'].toString().trim()
                              : '—',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  _ActionsMenu(
                    staffMode: staffMode,
                    periodDays: periodDays,
                    item: item,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatusChip(label: statusText, color: snap.statusColor()),
                  if (urgency != 'NORMAL')
                    _StatusChip(
                      label: urgency,
                      color: isDelayed
                          ? const Color(0xFFBA7517)
                          : isDisputed
                              ? const Color(0xFFA32D2D)
                              : snap.needsVerification
                                  ? const Color(0xFF0EA5E9)
                                  : status == ItemStockStatus.lowStock
                                      ? const Color(0xFFE65100)
                                      : snap.statusColor(),
                    ),
                ],
              ),
              if (deliveryCue != null) ...[
                const SizedBox(height: 6),
                deliveryCue,
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'System: ${formatStockQtyDisplay(unitDisplay, snap.systemQty)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Physical: ${formatStockQtyDisplay(unitDisplay, snap.physicalQty)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Difference: ${snap.diffLabel()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: snap.diffQty.abs() <= 0.001 ? HexaDsColors.textMuted : snap.statusColor(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Reorder: ${formatStockQtyDisplay(unitDisplay, snap.reorderLevel)} • Usage/day: ${usagePerDay.isFinite ? formatStockQtyDisplay(unitDisplay, usagePerDay) : '—'}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Stage: $lifecycleStage${hasPending && pendingDays != null ? ' · ${pendingDays}d' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: HexaDsColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Supplier: ${supplier != null && supplier.isNotEmpty ? supplier : '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: Text(
                      'ETA: $etaLabel',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Updated: ${updatedAt != null ? DateFormat('dd MMM yyyy').format(updatedAt) : '—'}${updatedBy != null && updatedBy.isNotEmpty ? ' · $updatedBy' : ''}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({
    required this.staffMode,
    required this.periodDays,
    required this.item,
  });

  final bool staffMode;
  final int periodDays;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = item['id']?.toString();
    final itemName = item['name']?.toString() ?? 'Item';
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded),
      padding: EdgeInsets.zero,
      itemBuilder: (ctx) {
        final s = ref.read(sessionProvider);
        final canOwner = s != null && sessionHasOwnerDashboard(s);
        final needsVerification = item['needs_verification'] == true;
        final common = <PopupMenuEntry<String>>[];

        common.add(
          PopupMenuItem<String>(
            value: 'detail',
            child: Row(
              children: const [
                Icon(Icons.open_in_new_rounded),
                SizedBox(width: 10),
                Text('Open item'),
              ],
            ),
          ),
        );

        if (staffMode) {
          common.add(
            PopupMenuItem<String>(
              value: 'verify',
              child: Row(
                children: const [
                  Icon(Icons.edit_rounded),
                  SizedBox(width: 10),
                  Text('Verify count'),
                ],
              ),
            ),
          );
          common.add(
            PopupMenuItem<String>(
              value: 'reorder_level',
              child: Row(
                children: const [
                  Icon(Icons.tune_rounded),
                  SizedBox(width: 10),
                  Text('Reorder level'),
                ],
              ),
            ),
          );
          common.add(
            PopupMenuItem<String>(
              value: 'notify_owner',
              child: Row(
                children: const [
                  Icon(Icons.notifications_active_outlined),
                  SizedBox(width: 10),
                  Text('Notify owner'),
                ],
              ),
            ),
          );
          return common;
        }

        if (canOwner) {
          if (needsVerification) {
            common.add(
              PopupMenuItem<String>(
                value: 'approve_verification',
                child: Row(
                  children: const [
                    Icon(Icons.rule_rounded),
                    SizedBox(width: 10),
                    Text('Approve verification'),
                  ],
                ),
              ),
            );
          }

          common.add(
            PopupMenuItem<String>(
              value: 'order_now',
              child: Row(
                children: const [
                  Icon(Icons.shopping_cart_outlined),
                  SizedBox(width: 10),
                  Text('Order now'),
                ],
              ),
            ),
          );
          common.add(
            PopupMenuItem<String>(
              value: 'reorder_list',
              child: Row(
                children: const [
                  Icon(Icons.playlist_add_check_rounded),
                  SizedBox(width: 10),
                  Text('Add to reorder list'),
                ],
              ),
            ),
          );
          common.add(
            PopupMenuItem<String>(
              value: 'update_stock',
              child: Row(
                children: const [
                  Icon(Icons.edit_rounded),
                  SizedBox(width: 10),
                  Text('Update stock'),
                ],
              ),
            ),
          );
          common.add(
            PopupMenuItem<String>(
              value: 'export_statement',
              child: Row(
                children: const [
                  Icon(Icons.picture_as_pdf_rounded),
                  SizedBox(width: 10),
                  Text('Export statement PDF'),
                ],
              ),
            ),
          );
        }

        return common;
      },
      onSelected: (v) async {
        switch (v) {
          case 'detail':
            context.push('/catalog/item/$id');
            return;
          case 'order_now':
            context.push('/purchase/new?itemId=$id');
            return;
          case 'reorder_list':
            await _addToReorderList(ref, id, context);
            return;
          case 'update_stock':
            await showQuickStockActionSheet(
              context: context,
              ref: ref,
              item: item,
            );
            return;
          case 'export_statement':
            try {
              final res = await exportShareItemStatementPdf(
                ref: ref,
                catalogItemId: id,
                itemName: itemName,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(res.ok ? 'Export started' : res.message),
                  duration: const Duration(seconds: 4),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(userFacingError(e))),
              );
            }
            return;
          case 'verify':
            await showQuickStockActionSheet(
              context: context,
              ref: ref,
              item: item,
            );
            return;
          case 'reorder_level':
            final unit =
                item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'bag';
            await showReorderLevelSheet(
              context: context,
              ref: ref,
              itemId: id,
              itemName: itemName,
              unit: unit,
              currentReorder: reorderLevelFromStockRow(item),
            );
            return;
          case 'notify_owner':
            await _notifyOwner(ref, id, itemName, context);
            return;
          case 'approve_verification':
            await showLowStockApprovalSheet(
              context: context,
              ref: ref,
              itemId: id,
              itemName: itemName,
            );
            return;
        }
      },
    );
  }

  Future<void> _notifyOwner(
    WidgetRef ref,
    String itemId,
    String itemName,
    BuildContext context,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).notifyOwnerStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Owner notified about $itemName'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _addToReorderList(
    WidgetRef ref,
    String itemId,
    BuildContext context,
  ) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).addItemToReorderList(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          );
      ref.invalidate(lowStockOperationsSummaryProvider);
      ref.invalidate(lowStockOperationsPageProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to reorder list')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }
}

