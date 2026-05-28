import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/app_period_provider.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import 'widgets/staff_home_dashboard_widgets.dart';
import 'widgets/staff_warehouse_totals_card.dart';
import 'widgets/staff_warehouse_difference_card.dart';

String _staffInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final list = parts.take(2).toList();
  if (list.isEmpty) return 'S';
  return list.map((w) => w[0].toUpperCase()).join();
}

String _pendingDeliverySubtitle(List<TradePurchase> pending) {
  if (pending.isEmpty) return 'Trucks waiting — open receive checklist';
  final first = pending.first.supplierName?.trim();
  if (first != null && first.isNotEmpty) {
    if (pending.length == 1) return 'From $first — tap to receive';
    return 'From $first + ${pending.length - 1} more';
  }
  return '${pending.length} orders waiting at warehouse';
}

String _staffFocusLabel(StaffHomeFocus f) => switch (f) {
      StaffHomeFocus.all => 'All tasks',
      StaffHomeFocus.barcode => 'Barcode & labels',
      StaffHomeFocus.stock => 'Stock & warehouse',
      StaffHomeFocus.purchase => 'Purchases & delivery',
    };

Future<void> _showStaffProfileSheet(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  final nameAsync = ref.read(staffDisplayNameProvider);
  final name = nameAsync.valueOrNull ?? 'Staff';
  final biz = session?.primaryBusiness.effectiveDisplayTitle ?? 'Workspace';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final currentFocus = ref.watch(staffHomeFocusProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          HexaColors.brandPrimary.withValues(alpha: 0.15),
                      child: Text(
                        _staffInitials(name),
                        style: HexaDsType.heading(
                          18,
                          color: HexaColors.brandPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: HexaDsType.heading(18)),
                          const SizedBox(height: 4),
                          Text(
                            'Role: Staff · $biz',
                            style: HexaDsType.body(
                              13,
                              color: HexaDsColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Home focus',
                  style: HexaDsType.heading(14),
                ),
                const SizedBox(height: 8),
                ...StaffHomeFocus.values.map((f) {
                  final selected = currentFocus == f;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected
                          ? HexaColors.brandPrimary
                          : HexaDsColors.textMuted,
                    ),
                    title: Text(_staffFocusLabel(f)),
                    onTap: () async {
                      await ref.read(staffHomeFocusProvider.notifier).setFocus(f);
                    },
                  );
                }),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                    side: BorderSide(color: Theme.of(ctx).colorScheme.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: Text('Log out of ${HexaColors.appName}?'),
                        content: const Text(
                          'You will need to sign in again to continue.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(sessionProvider.notifier).logout();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Staff shell home — scan-first dashboard (FEAT-5).
class StaffHomePage extends ConsumerWidget {
  const StaffHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(staffDisplayNameProvider);
    final name = nameAsync.valueOrNull ?? 'Staff';
    final initials = _staffInitials(name);
    final bellCount = ref.watch(notificationsUnreadCountProvider);
    final focus = ref.watch(staffHomeFocusProvider);
    final missingCount = ref.watch(staffMissingCodeCountProvider);
    final pendingDeliveries = ref.watch(staffPendingDeliveryCountProvider);
    final pendingList =
        ref.watch(staffPendingDeliveriesProvider).valueOrNull ?? const [];
    final lowCount =
        ref.watch(staffLowStockAlertsProvider).valueOrNull?.length ?? 0;
    final openingCount = ref.watch(staffOpeningStockCountProvider);
    final mismatchAsync = ref.watch(staffStockMismatchCountProvider);
    final mismatchCount = mismatchAsync.valueOrNull ?? 0;

    final showAttention = (staffHomeShowsPurchaseTools(focus) &&
            pendingDeliveries > 0) ||
        lowCount > 0 ||
        openingCount > 0 ||
        (staffHomeShowsBarcodeTools(focus) && missingCount > 0) ||
        mismatchCount > 0;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffTodayActivityProvider);
            ref.invalidate(staffTodayStockWorkProvider);
            ref.invalidate(staffLowStockAlertsProvider);
            ref.invalidate(staffRecentScansProvider);
            ref.invalidate(staffRecentActivityProvider);
            ref.invalidate(staffStockMismatchCountProvider);
            ref.invalidate(missingCodeItemsProvider);
            ref.invalidate(openingStockMissingProvider);
            ref.invalidate(tradePurchasesListProvider);
            ref.invalidate(stockOnHandTotalsProvider);
            ref.invalidate(stockTotalsProvider(AppPeriod.month));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              12,
              HexaOp.pageGutter,
              100,
            ),
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => _showStaffProfileSheet(context, ref),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          HexaColors.brandPrimary.withValues(alpha: 0.12),
                      child: Text(
                        initials,
                        style: HexaDsType.label(
                          12,
                          color: HexaColors.brandPrimary,
                        ).copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                        children: [
                          TextSpan(
                            text: name,
                            style: HexaDsType.heading(14),
                          ),
                          const TextSpan(text: ' · STAFF · '),
                          TextSpan(
                            text: DateFormat('EEE d MMM').format(DateTime.now()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => context.push('/notifications'),
                    icon: Badge(
                      isLabelVisible: bellCount > 0,
                      label: Text(
                        bellCount > 99 ? '99+' : '$bellCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeShiftSnapshotStrip(),
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeRecentScansStrip(),
              if (showAttention) ...[
                const SizedBox(height: HexaOp.sectionGap),
                const StaffHomeSectionHeader(
                  title: 'Needs attention',
                  subtitle: 'Tap to open and complete',
                ),
                if (staffHomeShowsPurchaseTools(focus) && pendingDeliveries > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.local_shipping_rounded,
                    title: 'Pending deliveries',
                    subtitle: _pendingDeliverySubtitle(pendingList),
                    count: pendingDeliveries,
                    accent: const Color(0xFFBA7517),
                    onTap: () => context.push('/staff/receive'),
                  ),
                if (lowCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.warning_amber_rounded,
                    title: 'Low stock',
                    subtitle: 'Update counts or reorder levels',
                    count: lowCount,
                    accent: const Color(0xFFDC2626),
                    onTap: () {
                      ref.read(stockListQueryProvider.notifier).state =
                          const StockListQuery(status: 'low', page: 1);
                      context.go('/staff/stock');
                    },
                  ),
                if (openingCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.inventory_outlined,
                    title: 'Opening stock',
                    subtitle: 'Items need initial stock setup',
                    count: openingCount,
                    accent: HexaColors.warning,
                    onTap: () => context.push('/stock/opening-setup'),
                  ),
                if (staffHomeShowsBarcodeTools(focus) && missingCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.qr_code_2_outlined,
                    title: 'Missing barcodes',
                    subtitle: 'Items need labels before bulk print',
                    count: missingCount,
                    accent: HexaColors.loss,
                    onTap: () => context.push('/stock/missing-barcodes'),
                  ),
                if (mismatchCount > 0)
                  StaffHomeAttentionTile(
                    icon: Icons.compare_arrows_rounded,
                    title: 'Stock mismatch',
                    subtitle: 'Physical count differs from system',
                    count: mismatchCount,
                    accent: const Color(0xFFA32D2D),
                    onTap: () => context.go('/reports'),
                  ),
              ],
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(
                title: 'Start here',
                subtitle: 'Most used actions for floor staff',
              ),
              Material(
                elevation: 2,
                shadowColor: HexaColors.brandPrimary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/barcode/scan'),
                  child: Ink(
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          HexaColors.brandPrimary,
                          HexaColors.brandPrimary.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Scan barcode',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/operations/checklist'),
                      icon: const Icon(Icons.checklist_rounded),
                      label: const Text('Checklist'),
                    ),
                  ),
                  if (staffHomeShowsPurchaseTools(focus)) ...[
                    const SizedBox(width: 10),
                    Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => context.push('/staff/quick-purchase'),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Cash buy'),
                      ),
                    ),
                  ],
                ],
              ),
              if (staffHomeShowsWarehouse(focus)) ...[
                const SizedBox(height: HexaOp.sectionGap),
                const StaffHomeSectionHeader(
                  title: 'Warehouse on hand',
                  subtitle: 'Totals across bags, kg, boxes, tins',
                ),
                const StaffWarehouseTotalsCard(),
                const SizedBox(height: HexaOp.cardGap),
                const StaffWarehouseDifferenceCard(),
              ],
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeRecentActivitySection(),
              const SizedBox(height: HexaOp.sectionGap),
              const StaffHomeSectionHeader(
                title: 'Tools',
                subtitle: 'Search, stock, labels, and history',
              ),
              StaffHomeToolsGrid(lowCount: lowCount, focus: focus),
            ],
          ),
        ),
      ),
    );
  }
}
