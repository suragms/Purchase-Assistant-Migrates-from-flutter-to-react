import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/providers/home_owner_dashboard_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/providers/home_breakdown_tab_providers.dart';
import '../../core/providers/home_dashboard_provider.dart';
import '../../core/providers/reports_provider.dart';
import '../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches;
import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/theme/hexa_colors.dart';
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
        break;
      case ShellBranch.history:
        invalidateTradePurchaseCaches(ref);
        break;
      case ShellBranch.reports:
        ref.invalidate(reportsPurchasesPayloadProvider);
        break;
      case ShellBranch.stock:
        ref.invalidate(stockListProvider);
        ref.invalidate(stockAlertCountsProvider);
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
    final stockAlertN = ref.watch(stockLowCountProvider).valueOrNull ?? 0;

    void go(int branch) {
      HapticFeedback.selectionClick();
      _syncShellBranch(branch);
      navigationShell.goBranch(branch);
    }

    final loc = routePath;
    final hideShellChrome = loc == '/reports' ||
        loc.startsWith('/reports/') ||
        loc == '/purchase';

    // Do not use a shell [Scaffold] with [bottomNavigationBar]: on web, nested
    // GoRouter [Navigator]s can interact badly with scaffold body layout so the
    // body gets ~zero height while the bar still paints — it then looks vertically
    // centered with a blank page. [SizedBox.expand] + [Column] keeps tabs + bar as
    // explicit flex siblings (see also [NoTransitionPage] in app_router).
    return SizedBox.expand(
      child: Material(
        key: const ValueKey<String>('main_shell'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
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
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
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
            Expanded(child: navigationShell),
            if (!hideShellChrome)
              _ShellBottomBar(
                selectedIndex: idx,
                stockBadgeCount: stockAlertN,
                onDestinationSelected: go,
              ),
          ],
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
  });

  final int selectedIndex;
  final int stockBadgeCount;
  final ValueChanged<int> onDestinationSelected;

  static const _fabOuter = 60.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPad = 6.0 +
        math.max(0.0, MediaQuery.viewPaddingOf(context).bottom * 0.2);
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
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
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
                                  label: 'History',
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
                    const SizedBox(width: 4),
                    SizedBox(
                      width: _fabOuter,
                      child: const Center(
                        child: _FabButton(),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                ),
                child: Icon(
                  ic,
                  size: 24,
                  color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
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
                color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
              ),
            ),
          ],
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(Icons.add_shopping_cart_outlined,
                      color: HexaColors.brandPrimary),
                  title: Text('New purchase',
                      style: HexaDsType.body(16,
                          color: HexaDsColors.textPrimary,
                          weight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push('/purchase/new');
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
                  leading: Icon(Icons.document_scanner_outlined,
                      color: HexaColors.brandPrimary),
                  title: Text('Scan bill',
                      style: HexaDsType.body(16,
                          color: HexaDsColors.textPrimary,
                          weight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push('/purchase/scan');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.inventory_outlined,
                      color: HexaColors.brandPrimary),
                  title: Text('Add catalog item',
                      style: HexaDsType.body(16,
                          color: HexaDsColors.textPrimary,
                          weight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push('/catalog/quick-add');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Quick add',
      button: true,
      enabled: true,
      excludeSemantics: true,
      child: Container(
        width: 56,
        height: 56,
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
            child: const Icon(Icons.add_rounded, size: 26, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
