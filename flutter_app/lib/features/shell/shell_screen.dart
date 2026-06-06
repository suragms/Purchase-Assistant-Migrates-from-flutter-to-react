import 'dart:math' as math;
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
import '../../core/design_system/hexa_operational_tokens.dart';
import '../../core/auth/session_notifier.dart';
import '../../core/auth/provider_api_guard.dart';
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
    // Keep provider aligned with IndexedStack index in the same frame (post-frame
    // sync left Home providers empty while the Home tab was already visible).
    if (ref.read(shellCurrentBranchProvider) != idx) {
      ref.read(shellCurrentBranchProvider.notifier).state = idx;
    }
    final routePath = GoRouterState.of(context).uri.path;
    final pathBranch = shellBranchIndexForPath(routePath);
    final isPushedModal = shellIsPushedModalPath(routePath);
    final navSelectedIndex =
        (pathBranch != null && !isPushedModal) ? pathBranch : idx;
    // Sync IndexedStack only for real branch routes — not barcode/settings pushes.
    if (pathBranch != null && !isPushedModal && pathBranch != idx) {
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
    final stockAlertN = providerSkipApi(ref)
        ? 0
        : ref.watch(notificationsUnreadCountProvider);
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width > 0 && width >= kShellRailMin;
    final railExtended = width > 0 && width >= kShellRailExtendedMin;
    final showBottomBar = width > 0 && width < kShellBottomNavMax;
    final session = ref.watch(sessionProvider);
    final biz = session?.primaryBusiness;

    void go(int branch) {
      HapticFeedback.selectionClick();
      ref.read(shellReturnBranchProvider.notifier).state = null;
      ref.read(shellCurrentBranchProvider.notifier).state = branch;
      navigationShell.goBranch(branch);
      final target = shellLocationForBranch(branch);
      final current = GoRouterState.of(context).uri.path;
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
          : _ShellBottomBar(
              selectedIndex: navSelectedIndex,
              stockBadgeCount: stockAlertN,
              onDestinationSelected: go,
              showFab: !hideFab,
            ),
    );

    final railWidget = NavigationRail(
      selectedIndex: navSelectedIndex,
      extended: railExtended,
      minExtendedWidth: kDesktopSidebarWidth,
      labelType: railExtended
          ? NavigationRailLabelType.all
          : NavigationRailLabelType.none,
      onDestinationSelected: go,
      trailing: railExtended && biz != null
          ? DesktopSideNavFooter(
              businessName: biz.effectiveDisplayTitle,
              roleLabel: biz.role.toUpperCase(),
              notificationCount: stockAlertN,
              onNotificationsTap: () => context.push('/notifications'),
              onSettingsTap: () => context.push('/settings'),
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
          label: Text('Purchases'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search_rounded),
          selectedIcon: Icon(Icons.manage_search_rounded),
          label: Text('Search'),
        ),
      ],
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
      canPop: idx == ShellBranch.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
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
                                    badgeCount: stockBadgeCount,
                                    dotOnly: true,
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
              Navigator.of(context).pop();
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
              Navigator.of(context).pop();
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
              Navigator.of(context).pop();
              context.push('/barcode/bulk-print');
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
