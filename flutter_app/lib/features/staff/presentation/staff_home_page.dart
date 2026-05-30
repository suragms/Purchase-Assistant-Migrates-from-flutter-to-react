import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/providers/app_period_provider.dart';
import '../../../core/providers/delivery_pipeline_provider.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'widgets/staff_home_dashboard_widgets.dart';
import 'widgets/staff_home_pending_delivery_cards.dart';

String _staffInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final list = parts.take(2).toList();
  if (list.isEmpty) return 'S';
  return list.map((w) => w[0].toUpperCase()).join();
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
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/staff/settings');
                  },
                ),
                const SizedBox(height: 8),
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

void _invalidateStaffHomeRefresh(WidgetRef ref) {
  ref.invalidate(staffTodayActivityProvider);
  ref.invalidate(staffTodayStockWorkProvider);
  ref.invalidate(staffLowStockAlertsProvider);
  ref.invalidate(staffRecentScansProvider);
  ref.invalidate(staffRecentActivityProvider);
  ref.invalidate(staffStockMismatchCountProvider);
  ref.invalidate(missingCodeItemsProvider);
  ref.invalidate(openingStockMissingProvider);
  ref.invalidate(staffTradePurchasesHistoryProvider);
  ref.invalidate(deliveryPipelineProvider);
  ref.invalidate(stockOnHandTotalsProvider);
  ref.invalidate(stockTotalsProvider(AppPeriod.month));
  ref.invalidate(stockStatusCountsProvider);
}

/// Staff shell home — floor KPIs, warehouse stats, tools.
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
    final lowCount = ref.watch(staffLowStockAttentionCountProvider);
    final openingCount = ref.watch(staffOpeningStockCountProvider);
    final mismatchAsync = ref.watch(staffStockMismatchCountProvider);
    final mismatchCount = mismatchAsync.valueOrNull ?? 0;
    final kpisAsync = ref.watch(staffDeliveryPipelineKpisProvider);
    final lowStockAsync = ref.watch(staffLowStockAlertsProvider);

    final showAttention = (staffHomeShowsPurchaseTools(focus) &&
            pendingDeliveries > 0) ||
        lowCount > 0 ||
        openingCount > 0 ||
        (staffHomeShowsBarcodeTools(focus) && missingCount > 0) ||
        mismatchCount > 0;

    final criticalError = kpisAsync.hasError
        ? kpisAsync.error
        : lowStockAsync.hasError
            ? lowStockAsync.error
            : null;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _invalidateStaffHomeRefresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HexaOp.pageGutter,
              8,
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
              if (criticalError != null) ...[
                const SizedBox(height: HexaOp.cardGap),
                FriendlyLoadError(
                  message:
                      'Could not load floor data — pull to retry or sign in again.',
                  onRetry: () => _invalidateStaffHomeRefresh(ref),
                ),
              ],
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeFloorKpiRow(),
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeSectionHeader(
                title: 'Warehouse & purchases',
                subtitle: 'On-hand stock and this month',
              ),
              const StaffHomeWarehousePurchaseStats(),
              if (pendingDeliveries > 0) ...[
                const SizedBox(height: HexaOp.cardGap),
                const StaffHomeSectionHeader(
                  title: 'Pending deliveries',
                  subtitle: 'Verify arrivals on the floor',
                ),
                const StaffHomePendingDeliveryCards(),
              ],
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeSectionHeader(
                title: 'Your shift today',
                subtitle: 'Scans, stock updates, purchases',
              ),
              const StaffHomeShiftSnapshotStrip(),
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeSectionHeader(
                title: 'Tools',
                subtitle: 'Search, stock, labels, and low stock',
              ),
              StaffHomeToolsGrid(lowCount: lowCount, focus: focus),
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeSectionHeader(
                title: 'Start here',
                subtitle: 'Scan and quick actions',
              ),
              Material(
                elevation: 2,
                shadowColor: HexaColors.brandPrimary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.go('/staff/scan'),
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
              if (staffHomeShowsPurchaseTools(focus)) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/staff/quick-purchase'),
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: const Text('Cash buy'),
                  ),
                ),
              ],
              if (showAttention &&
                  (openingCount > 0 ||
                      (staffHomeShowsBarcodeTools(focus) && missingCount > 0) ||
                      mismatchCount > 0)) ...[
                const SizedBox(height: HexaOp.cardGap),
                const StaffHomeSectionHeader(
                  title: 'Needs attention',
                  subtitle: 'Other warehouse items',
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
              const SizedBox(height: HexaOp.cardGap),
              const StaffHomeSectionHeader(
                title: 'Recent activity',
                subtitle: 'Latest stock and warehouse updates',
              ),
              const StaffHomeRecentActivitySection(),
            ],
          ),
        ),
      ),
    );
  }
}
