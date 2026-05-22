import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
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
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final idx = navigationShell.currentIndex;

    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    void go(int branch) {
      HapticFeedback.selectionClick();
      _syncStaffBranch(branch);
      navigationShell.goBranch(branch);
    }

    return SizedBox.expand(
      child: Material(
        key: const ValueKey<String>('staff_shell'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
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
            _StaffShellBottomBar(
              selectedIndex: idx,
              onDestinationSelected: go,
            ),
          ],
        ),
            Positioned(
              right: 16,
              bottom: 72 + MediaQuery.viewPaddingOf(context).bottom,
              child: FloatingActionButton(
                heroTag: 'staff_scan_fab',
                tooltip: 'Scan barcode',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  navigationShell.goBranch(StaffShellBranch.scan);
                },
                child: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffShellBottomBar extends StatelessWidget {
  const _StaffShellBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

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
                        selected: selectedIndex == StaffShellBranch.history,
                        icon: Icons.receipt_long_outlined,
                        selectedIcon: Icons.receipt_long_rounded,
                        label: 'History',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.history),
                      ),
                    ),
                    Expanded(
                      child: _StaffNavTile(
                        selected: selectedIndex == StaffShellBranch.search,
                        icon: Icons.search_rounded,
                        selectedIcon: Icons.manage_search_rounded,
                        label: 'Search',
                        onTap: () =>
                            onDestinationSelected(StaffShellBranch.search),
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
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

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
              child: Icon(
                ic,
                size: 24,
                color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
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
