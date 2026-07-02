import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/notification_center_provider.dart'
    show notificationCenterCoordinatorProvider;
import '../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/auth/session_notifier.dart';
import '../../core/auth/provider_api_guard.dart';
import '../../core/router/navigation_ext.dart';
import '../../core/router/shell_navigation.dart';
import '../../core/design_system/hexa_desktop_layout.dart';
import '../../core/design_system/hexa_responsive.dart';
import '../../core/theme/hexa_colors.dart';
import 'app_shell.dart';
import 'responsive_shell_layout.dart';
import 'shell_branch_provider.dart';
import 'business_write_stock_listener.dart';
import 'shell_realtime_listener.dart';
import 'shell_tab_auto_refresh_listener.dart';

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
      clearStuckAuthGates(ref);
      _syncShellBranch(widget.navigationShell.currentIndex);
    });
  }

  @override
  void didUpdateWidget(ShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = widget.navigationShell.currentIndex;
    if (oldWidget.navigationShell.currentIndex != idx) {
      _syncShellBranch(idx);
    }
  }

  void _syncShellBranch(int idx) {
    if (!mounted) return;
    if (ref.read(shellCurrentBranchProvider) == idx) return;
    clearStuckAuthGates(ref);
    // Only sync branch index — do NOT invalidate providers here (caused
    // hundreds of parallel refetches + StaleHomeDashboardFetch loops on web).
    ref.read(shellCurrentBranchProvider.notifier).state = idx;
  }

  @override
  Widget build(BuildContext context) {
    if (!providerSkipApi(ref)) {
      ref.watch(notificationCenterCoordinatorProvider);
    }
    final navigationShell = widget.navigationShell;
    final idx = navigationShell.currentIndex;
    if (ref.read(shellCurrentBranchProvider) != idx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncShellBranch(idx);
      });
    }
    final router = GoRouter.maybeOf(context);
    final routePath = router?.state.uri.path ?? '/home';
    final pathBranch = shellBranchIndexForPath(routePath);
    final isPushedModal = shellIsPushedModalPath(routePath);
    final isPrimaryTab = shellIsPrimaryTabLocation(routePath);
    final rawNavIndex = (pathBranch != null && !isPushedModal && isPrimaryTab)
        ? pathBranch
        : idx;
    // NavigationRail asserts selectedIndex is in [0, destinations.length).
    final navSelectedIndex = rawNavIndex.clamp(ShellBranch.home, ShellBranch.search);
    // Sync IndexedStack only for shell tab URLs — not pushed overlays (/catalog/*, etc.).
    if (pathBranch != null &&
        !isPushedModal &&
        isPrimaryTab &&
        pathBranch != idx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(shellCurrentBranchProvider.notifier).state = pathBranch;
        navigationShell.goBranch(pathBranch);
      });
    } else if (!isPushedModal &&
        routePath == '/home' &&
        idx != ShellBranch.home) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(shellCurrentBranchProvider.notifier).state = ShellBranch.home;
        navigationShell.goBranch(ShellBranch.home);
      });
    }
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width > 0 && width >= kShellRailMin;
    final railExtended = width > 0 && width >= kShellRailExtendedMin;
    final showBottomBar = width > 0 && width < kShellBottomNavMax;

    void go(int branch) {
      HapticFeedback.selectionClick();
      ref.read(shellReturnBranchProvider.notifier).state = null;
      ref.read(shellCurrentBranchProvider.notifier).state = branch;
      navigationShell.goBranch(branch);
      final target = shellLocationForBranch(branch);
      final current = GoRouter.maybeOf(context)?.state.uri.path ?? routePath;
      if (current != target && !current.startsWith('$target/')) {
        context.go(target);
      }
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
    final shellBody = AppShellBody(
      navigationShell: navigationShell,
      bottomBar: hideShellChrome || !showBottomBar
          ? null
          : _ShellBottomBarHost(
              selectedIndex: navSelectedIndex,
              onDestinationSelected: go,
              showFab: !hideFab,
            ),
    );

    final railWidget = _StableNavRail(
      selectedIndex: navSelectedIndex,
      extended: railExtended,
      onDestinationSelected: go,
      onNotificationsTap: () => context.push('/notifications'),
      onSettingsTap: () => context.push('/settings'),
    );

    final rail = showRail
        ? (railExtended
            ? railWidget
            : SizedBox(
                width: kShellCompactRailWidth,
                child: railWidget,
              ))
        : const SizedBox.shrink();

    return PopScope(
      canPop: !isPrimaryTab || idx == ShellBranch.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isPrimaryTab) return;
        if (idx == ShellBranch.reports || idx == ShellBranch.stock) {
          go(ShellBranch.home);
        } else if (idx != ShellBranch.home) {
          go(ShellBranch.home);
        }
      },
      child: BusinessWriteStockListener(
        child: ShellRealtimeListener(
          child: ShellTabAutoRefreshListener(
            child: SizedBox.expand(
              child: Material(
                key: const ValueKey<String>('main_shell'),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: ResponsiveShellLayout(
                  rail: rail,
                  body: shellBody,
                  railMinWidth: kShellRailMin,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StableNavRail extends ConsumerWidget {
  const _StableNavRail({
    required this.selectedIndex,
    required this.extended,
    required this.onDestinationSelected,
    required this.onNotificationsTap,
    required this.onSettingsTap,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onNotificationsTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAlertN = providerSkipApi(ref)
        ? 0
        : ref.watch(notificationsUnreadCountProvider);
    final biz = ref.watch(sessionProvider)?.primaryBusiness;

    return NavigationRail(
      selectedIndex: selectedIndex,
      extended: extended,
      minExtendedWidth: kDesktopSidebarWidth,
      labelType: extended
          ? NavigationRailLabelType.all
          : NavigationRailLabelType.none,
      onDestinationSelected: onDestinationSelected,
      trailing: extended && biz != null
          ? DesktopSideNavFooter(
              businessName: biz.effectiveDisplayTitle,
              roleLabel: biz.role.toUpperCase(),
              notificationCount: stockAlertN,
              onNotificationsTap: onNotificationsTap,
              onSettingsTap: onSettingsTap,
            )
          : null,
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
          label: Text('History'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.manage_search_rounded),
          label: Text('Search'),
        ),
      ],
    );
  }
}

class _ShellBottomBarHost extends ConsumerWidget {
  const _ShellBottomBarHost({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.showFab,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showFab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockBadgeCount = providerSkipApi(ref)
        ? 0
        : ref.watch(notificationsUnreadCountProvider);
    return _ShellBottomBar(
      selectedIndex: selectedIndex,
      stockBadgeCount: stockBadgeCount,
      onDestinationSelected: onDestinationSelected,
      showFab: showFab,
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
    
    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              elevation: 8,
              shadowColor: Colors.black26,
              color: cs.surface.withValues(alpha: 0.90),
              child: SizedBox(
                height: 76, // Height set to 76 (between 72 and 80)
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _ShellNavTile(
                          selected: selectedIndex == 0,
                          icon: Icons.grid_view_outlined,
                          selectedIcon: Icons.grid_view_rounded,
                          label: 'Home',
                          badgeCount: stockBadgeCount,
                          dotOnly: true,
                          onTap: () => onDestinationSelected(0),
                        ),
                      ),
                      Expanded(
                        child: _ShellNavTile(
                          selected: selectedIndex == 1,
                          icon: Icons.inventory_2_outlined,
                          selectedIcon: Icons.inventory_2_rounded,
                          label: 'Stock',
                          onTap: () => onDestinationSelected(1),
                        ),
                      ),
                      Expanded(
                        child: _ShellNavTile(
                          selected: selectedIndex == 2,
                          icon: Icons.bar_chart_outlined,
                          selectedIcon: Icons.bar_chart_rounded,
                          label: 'Reports',
                          onTap: () => onDestinationSelected(2),
                        ),
                      ),
                      if (showFab) ...[
                        const SizedBox(width: 4),
                        const SizedBox(
                          width: _fabOuter,
                          child: Center(
                            child: _FabButton(),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: _ShellNavTile(
                          selected: selectedIndex == 3,
                          icon: Icons.receipt_long_outlined,
                          selectedIcon: Icons.receipt_long_rounded,
                          label: 'History',
                          onTap: () => onDestinationSelected(3),
                        ),
                      ),
                      Expanded(
                        child: _ShellNavTile(
                          selected: selectedIndex == 4,
                          icon: Icons.search_rounded,
                          selectedIcon: Icons.manage_search_rounded,
                          label: 'Search',
                          onTap: () => onDestinationSelected(4),
                        ),
                      ),
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
    this.dotOnly = false,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final bool dotOnly;

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
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
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
                child: dotOnly
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            ic,
                            size: 20,
                            color: selected
                                ? HexaColors.brandPrimary
                                : cs.onSurfaceVariant,
                          ),
                          if (badgeCount > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Badge(
                        isLabelVisible: badgeCount > 0,
                        label: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
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
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
                  ),
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
    showHexaBottomSheet<void>(
      context: context,
      compact: true,
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
              Navigator.of(context).pop();
              pushPurchaseNew(context);
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
              Navigator.of(context).pop();
              pushCatalogQuickAdd(context);
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
              Navigator.of(context).pop();
              pushBarcodeScan(context);
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
              Navigator.of(context).pop();
              pushOverlayRoute(context, '/barcode/bulk-print');
            },
          ),
          ListTile(
            leading: Icon(Icons.tune_rounded, color: HexaColors.brandPrimary),
            title: Text('Stock adjustment',
                style: HexaDsType.body(16,
                    color: HexaDsColors.textPrimary,
                    weight: FontWeight.w700)),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/stock');
            },
          ),
        ],
      ),
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
