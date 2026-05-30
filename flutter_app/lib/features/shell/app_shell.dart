/// Shared owner/staff shell chrome ([AppShellBody], connectivity banners).
library;

export 'app_shell_banners.dart';

import 'package:flutter/material.dart';

import '../../core/theme/hexa_colors.dart';
import 'app_shell_banners.dart';

enum AppShellRole { owner, staff }

/// Column layout used by [ShellScreen] and [StaffShellScreen]: banners + tab body + nav.
class AppShellBody extends StatelessWidget {
  const AppShellBody({
    super.key,
    required this.navigationShell,
    this.topBanners = const [],
    this.bottomBar,
    this.showConnectivityBanner = true,
  });

  final Widget navigationShell;
  final List<Widget> topBanners;
  final Widget? bottomBar;
  final bool showConnectivityBanner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...topBanners,
        if (showConnectivityBanner) const AppShellConnectivityBanners(),
        Expanded(
          child: ColoredBox(
            color: HexaColors.brandBackground,
            child: navigationShell,
          ),
        ),
        if (bottomBar != null) bottomBar!,
      ],
    );
  }
}
