import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/services/offline_store.dart';
import '../../core/providers/home_owner_dashboard_providers.dart'
    show
        homeInventorySummaryProvider,
        homeRecentActivityFeedProvider,
        stockAuditPeriodProvider;
import '../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../core/providers/stock_providers.dart';
import '../../core/providers/home_breakdown_tab_providers.dart';
import '../../core/providers/home_dashboard_provider.dart';
import '../../core/providers/reports_provider.dart';
import '../../core/providers/realtime_events_provider.dart';
import '../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches;
import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/design_system/hexa_operational_tokens.dart';
import '../../core/design_system/hexa_responsive.dart';
import '../../core/theme/hexa_colors.dart';
import 'responsive_shell_layout.dart';
import 'shell_branch_provider.dart';

/// Shell: Home | Stock | Reports | History | Search in one row, then [+] (no overlap).
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncShellBranch(widget.navigationShell.currentIndex);
    });
  }

  @override
  void didUpdateWidget(ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = widget.navigationShell.currentIndex;
    if (oldWidget.navigationShell.currentIndex != idx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncShellBranch(idx);
      });
    }
  }

  void _syncShellBranch(int idx) {
    if (!mounted) return;
    final prev = ref.read(shellCurrentBranchProvider);
    if (prev == idx) return;
    ref.read(shellCurrentBranchProvider.notifier).state = idx;
    switch (idx) {
      case ShellBranch.home:
        ref.invalidate(homeDashboardDataProvider);
        ref.invalidate(homeShellReportsProvider);
        ref.invalidate(homeInventorySummaryProvider);
        ref.invalidate(stockAuditPeriodProvider);
        ref.invalidate(homeRecentActivityFeedProvider);
        break;
      case ShellBranch.history:
        invalidateTradePurchaseCaches(ref);
        break;
      case ShellBranch.reports:
        ref.invalidate(reportsPurchasesPayloadProvider);
        break;
      case ShellBranch.stock:
        ref.invalidate(stockListProvider);
        ref.invalidate(stockStatusCountsProvider);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final idx = navigationShell.currentIndex;
    final routePath = GoRouterState.of(context).uri.path;
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);
    final pendingSync = OfflineStore.getPendingEntries().length;
    final stockAlertN = ref.watch(notificationsUnreadCountProvider);
    ref.watch(realtimeInvalidationProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    void go(int branch) {
      HapticFeedback.selectionClick();
      _syncShellBranch(branch);
      navigationShell.goBranch(branch);
    }

    final loc = routePath;
    final hideShellChrome = loc == '/reports' ||
        loc.startsWith('/reports/') ||
        loc == '/purchase' ||
        idx == ShellBranch.stock ||
        loc.startsWith('/stock');
    final hideFab = loc == '/notifications' ||
        loc.startsWith('/notifications/') ||
        loc.startsWith('/catalog/item/');

    // Do not use a shell [Scaffold] with [bottomNavigationBar]: on web, nested
    // GoRouter [Navigator]s can interact badly with scaffold body layout so the
    // body gets ~zero height while the bar still paints — it then looks vertically
    // centered with a blank page. [SizedBox.expand] + [Column] keeps tabs + bar as
    // explicit flex siblings (see also [NoTransitionPage] in app_router).
    final shellBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          Semantics(
            liveRegion: true,
            container: true,
            label: "You're offline — showing cached data",
            child: Material(
              color: const Color(0xFFF59E0B),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HexaDsLayout.pageGutter,
                  vertical: HexaDsSpace.xs + 2,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 18, color: Color(0xFF1C1917)),
                    const SizedBox(width: HexaDsLayout.inlineGap),
                    Expanded(
                      child: Text(
                        "You're offline — showing cached data",
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF1C1917),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!offline && pendingSync > 0)
          Material(
            color: const Color(0xFFE3F2FD),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HexaDsLayout.pageGutter,
                vertical: HexaDsSpace.xs + 2,
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 18, color: Color(0xFF1565C0)),
                  const SizedBox(width: HexaDsLayout.inlineGap),
                  Expanded(
                    child: Text(
                      pendingSync == 1
                          ? '1 change pending sync'
                          : '$pendingSync changes pending sync',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF1565C0),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: navigationShell),
        if (!hideShellChrome)
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 900) return const SizedBox.shrink();
              return _ShellBottomBar(
                selectedIndex: idx,
                stockBadgeCount: stockAlertN,
                onDestinationSelected: go,
                showFab: !hideFab,
              );
            },
          ),
      ],
    );

    final rail = NavigationRail(
      selectedIndex: idx,
      extended: MediaQuery.sizeOf(context).width >= 1100,
      labelType: MediaQuery.sizeOf(context).width < 380
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      onDestinationSelected: go,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2_rounded),
          label: Text('Stock'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart_rounded),
          label: Text('Reports'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: Text('Purchases'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.manage_search_rounded),
          label: Text('Search'),
        ),
      ],
    );

    return SizedBox.expand(
      child: Material(
        key: const ValueKey<String>('main_shell'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ResponsiveShellLayout(
          rail: hideShellChrome && !isDesktop ? const SizedBox.shrink() : rail,
          body: shellBody,
        ),
      ),
    );
  }
}

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.selectedIndex,
    required this.stockBadgeCount,
    required this.onDestinationSelected,
    required this.showFab,
  });

  final int selectedIndex;
  final int stockBadgeCount;
  final ValueChanged<int> onDestinationSelected;
  final bool showFab;

  static const _fabOuter = 48.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad =
        8.0 + math.max(8.0, MediaQuery.viewPaddingOf(context).bottom);
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomPad),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            elevation: 8,
            shadowColor: Colors.black26,
            color: cs.surface.withValues(alpha: 0.90),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: HexaOp.bottomNavMax,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxW = constraints.maxWidth;
                            const nTabs = 5;
                            final per = maxW > 0 ? maxW / nTabs : 0.0;
                            var w = math.max(42.0, per);
                            if (w * nTabs > maxW) {
                              w = per;
                            }
                            return Row(
                              children: [
                                SizedBox(
                                  width: w,
                                  child: _ShellNavTile(
                                    selected: selectedIndex == 0,
                                    icon: Icons.grid_view_outlined,
                                    selectedIcon: Icons.grid_view_rounded,
                                    label: 'Home',
                                    onTap: () => onDestinationSelected(0),
                                  ),
                                ),
                                SizedBox(
                                  width: w,
                                  child: _ShellNavTile(
                                    selected: selectedIndex == 1,
                                    icon: Icons.inventory_2_outlined,
                                    selectedIcon: Icons.inventory_2_rounded,
                                    label: 'Stock',
                                    badgeCount: stockBadgeCount,
                                    onTap: () => onDestinationSelected(1),
                                  ),
                                ),
                                SizedBox(
                                  width: w,
                                  child: _ShellNavTile(
                                    selected: selectedIndex == 2,
                                    icon: Icons.bar_chart_outlined,
                                    selectedIcon: Icons.bar_chart_rounded,
                                    label: 'Reports',
                                    onTap: () => onDestinationSelected(2),
                                  ),
                                ),
                                SizedBox(
                                  width: w,
                                  child: _ShellNavTile(
                                    selected: selectedIndex == 3,
                                    icon: Icons.receipt_long_outlined,
                                    selectedIcon: Icons.receipt_long_rounded,
                                    label: 'Purchases',
                                    onTap: () => onDestinationSelected(3),
                                  ),
                                ),
                                SizedBox(
                                  width: w,
                                  child: _ShellNavTile(
                                    selected: selectedIndex == 4,
                                    icon: Icons.search_rounded,
                                    selectedIcon: Icons.manage_search_rounded,
                                    label: 'Search',
                                    onTap: () => onDestinationSelected(4),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (showFab) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width: _fabOuter,
                          child: const Center(
                            child: _FabButton(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellNavTile extends StatelessWidget {
  const _ShellNavTile({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ic = selected ? selectedIcon : icon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: HexaResponsive.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? HexaColors.brandPrimary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Badge(
                  isLabelVisible: badgeCount > 0,
                  label: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                  child: Icon(
                    ic,
                    size: 20,
                    color: selected
                        ? HexaColors.brandPrimary
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color:
                      selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FabButton extends StatelessWidget {
  const _FabButton();

  void _openQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return HexaResponsiveSheetViewport(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(Icons.add_shopping_cart_outlined,
                    color: HexaColors.brandPrimary),
                title: Text('Add purchase',
                    style: HexaDsType.body(16,
                        color: HexaDsColors.textPrimary,
                        weight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/purchase/new');
                },
              ),
              ListTile(
                leading: Icon(Icons.inventory_outlined,
                    color: HexaColors.brandPrimary),
                title: Text('Add item',
                    style: HexaDsType.body(16,
                        color: HexaDsColors.textPrimary,
                        weight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/catalog/quick-add');
                },
              ),
              ListTile(
                leading: Icon(Icons.qr_code_scanner_rounded,
                    color: HexaColors.brandPrimary),
                title: Text('Scan barcode',
                    style: HexaDsType.body(16,
                        color: HexaDsColors.textPrimary,
                        weight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/barcode/scan');
                },
              ),
              ListTile(
                leading: Icon(Icons.qr_code_2_rounded,
                    color: HexaColors.brandPrimary),
                title: Text('Print labels',
                    style: HexaDsType.body(16,
                        color: HexaDsColors.textPrimary,
                        weight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/barcode/bulk-print');
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.tune_rounded, color: HexaColors.brandPrimary),
                title: Text('Stock adjustment',
                    style: HexaDsType.body(16,
                        color: HexaDsColors.textPrimary,
                        weight: FontWeight.w700)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go('/stock');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'New purchase',
      button: true,
      enabled: true,
      excludeSemantics: true,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: HexaColors.ctaGradient,
          shape: BoxShape.circle,
          boxShadow: HexaColors.heroShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.mediumImpact();
              _openQuickActions(context);
            },
            child: const Icon(Icons.add_rounded, size: 24, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
