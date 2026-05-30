import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_desktop_layout.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/providers/notification_center_provider.dart'
    show notificationCenterCoordinatorProvider;
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/api_degraded_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/staff_home_providers.dart'
    show staffPendingDeliveryCountProvider;
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/hexa_count_badge.dart';
import '../../shell/app_shell.dart';
import '../../shell/shell_realtime_listener.dart';
import '../staff_shell_branch_provider.dart';

/// Staff shell: Home | Stock | Scan | Search — same offline banner pattern as [ShellScreen].
class StaffShellScreen extends ConsumerStatefulWidget {
  const StaffShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<StaffShellScreen> createState() => _StaffShellScreenState();
}

class _StaffShellScreenState extends ConsumerState<StaffShellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncStaffBranch(widget.navigationShell.currentIndex);
    });
  }

  @override
  void didUpdateWidget(StaffShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = widget.navigationShell.currentIndex;
    if (oldWidget.navigationShell.currentIndex != idx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncStaffBranch(idx);
      });
    }
  }

  void _syncStaffBranch(int idx) {
    if (!mounted) return;
    final prev = ref.read(staffShellCurrentBranchProvider);
    if (prev == idx) return;
    ref.read(staffShellCurrentBranchProvider.notifier).state = idx;
    switch (idx) {
      case StaffShellBranch.home:
        ref.invalidate(homeDashboardDataProvider);
        break;
      case StaffShellBranch.stock:
        ref.invalidate(stockListProvider);
        ref.invalidate(stockLowCountProvider);
        break;
      case StaffShellBranch.tasks:
        ref.invalidate(checklistTodayProvider);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationCenterCoordinatorProvider);
    final navigationShell = widget.navigationShell;
    final idx = navigationShell.currentIndex;
    final routePath = GoRouterState.of(context).uri.path;

    final sessionHint = ref.watch(apiDegradedProvider);
    final width = MediaQuery.sizeOf(context).width;
    final showsRail = width >= kNavigationRailMin;
    final railExtended = width >= kDesktopMin;
    final session = ref.watch(sessionProvider);
    final biz = session?.primaryBusiness;
    final notifN = ref.watch(notificationsUnreadCountProvider);
    final pendingDel = ref.watch(staffPendingDeliveryCountProvider);

    void go(int branch) {
      HapticFeedback.selectionClick();
      _syncStaffBranch(branch);
      navigationShell.goBranch(branch);
    }

    return ShellRealtimeListener(
      child: SizedBox.expand(
        child: Material(
          key: const ValueKey<String>('staff_shell'),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showsRail)
                  NavigationRail(
                    selectedIndex: idx,
                    extended: railExtended,
                    minExtendedWidth: kDesktopSidebarWidth,
                    onDestinationSelected: go,
                    trailing: railExtended && biz != null
                        ? DesktopSideNavFooter(
                            businessName: biz.effectiveDisplayTitle,
                            roleLabel: biz.role.toUpperCase(),
                            notificationCount: notifN,
                            onNotificationsTap: () =>
                                context.push('/notifications'),
                          )
                        : null,
                    destinations: [
                      const NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: Text('Home'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: Text('Stock'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.qr_code_scanner_outlined),
                        selectedIcon: Icon(Icons.qr_code_scanner_rounded),
                        label: Text('Scan'),
                      ),
                      NavigationRailDestination(
                        icon: Badge(
                          isLabelVisible: pendingDel > 0,
                          label: Text(
                            pendingDel > 99 ? '99+' : '$pendingDel',
                          ),
                          backgroundColor: const Color(0xFFEA580C),
                          child: const Icon(Icons.local_shipping_outlined),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: pendingDel > 0,
                          label: Text(
                            pendingDel > 99 ? '99+' : '$pendingDel',
                          ),
                          backgroundColor: const Color(0xFFEA580C),
                          child: const Icon(Icons.local_shipping_rounded),
                        ),
                        label: const Text('Deliveries'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.checklist_outlined),
                        selectedIcon: Icon(Icons.checklist_rounded),
                        label: Text('Tasks'),
                      ),
                    ],
                  ),
                Expanded(
                  child: AppShellBody(
                    navigationShell: navigationShell,
                    topBanners: [
                      if (sessionHint != null)
                        Material(
                          color: const Color(0xFFFFEBEE),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HexaDsLayout.pageGutter,
                              vertical: HexaDsSpace.xs + 2,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_reset_rounded,
                                    size: 18, color: Color(0xFFC62828)),
                                const SizedBox(width: HexaDsLayout.inlineGap),
                                Expanded(
                                  child: Text(
                                    sessionHint,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: const Color(0xFF7F1D1D),
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
                    ],
                    bottomBar: showsRail
                        ? null
                        : _StaffShellBottomBar(
                            selectedIndex: idx,
                            pendingDeliveryCount: pendingDel,
                            onDestinationSelected: go,
                          ),
                  ),
                ),
              ],
            ),
            if (idx != StaffShellBranch.home &&
                idx != StaffShellBranch.scan &&
                idx != StaffShellBranch.stock &&
                routePath != '/notifications' &&
                !routePath.startsWith('/catalog/item/'))
              Positioned(
                right: 16,
                bottom: 68 + MediaQuery.viewPaddingOf(context).bottom,
                child: FloatingActionButton.small(
                  heroTag: 'staff_scan_fab',
                  tooltip: 'Scan barcode',
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    navigationShell.goBranch(StaffShellBranch.scan);
                  },
                  child: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _StaffShellBottomBar extends StatelessWidget {
  const _StaffShellBottomBar({
    required this.selectedIndex,
    required this.pendingDeliveryCount,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final int pendingDeliveryCount;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad =
        6.0 + math.max(0.0, MediaQuery.viewPaddingOf(context).bottom * 0.2);
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.home,
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.home),
                      ),
                    ),
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.stock,
                        icon: Icons.inventory_2_outlined,
                        selectedIcon: Icons.inventory_2_rounded,
                        label: 'Stock',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.stock),
                      ),
                    ),
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.scan,
                        icon: Icons.qr_code_scanner_outlined,
                        selectedIcon: Icons.qr_code_scanner_rounded,
                        label: 'Scan',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.scan),
                      ),
                    ),
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.deliveries,
                        icon: Icons.local_shipping_outlined,
                        selectedIcon: Icons.local_shipping_rounded,
                        label: 'Deliveries',
                        badge: pendingDeliveryCount,
                        badgeColor: const Color(0xFFEA580C),
                        onTap: () => onDestinationSelected(
                            StaffShellBranch.deliveries),
                      ),
                    ),
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.tasks,
                        icon: Icons.checklist_outlined,
                        selectedIcon: Icons.checklist_rounded,
                        label: 'Tasks',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.tasks),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffNavTile extends StatelessWidget {
  const _StaffNavTile({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final Color? badgeColor;

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
                child: HexaCountBadge(
                  count: badge,
                  backgroundColor: badgeColor ?? const Color(0xFFDC2626),
                  child: Icon(
                    ic,
                    size: 24,
                    color:
                        selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
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
