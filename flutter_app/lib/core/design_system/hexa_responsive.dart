import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hexa_ds_tokens.dart';
import 'hexa_operational_tokens.dart';

/// Spec-aligned breakpoints (DESKTOP_DESIGN_SPEC.md).
const double kMobileMax = 599;
const double kTabletMin = 600;
const double kDesktopMin = 1024;

/// Navigation rail shows at tablet width and above (legacy alias).
const double kNavigationRailMin = 900;

/// Shell: bottom navigation only below this width.
const double kShellBottomNavMax = 600;

/// Shell: left NavigationRail from tablet up.
const double kShellRailMin = 600;

/// Shell: extended rail with labels (desktop).
const double kShellRailExtendedMin = 900;

/// Compact NavigationRail width (icons only).
const double kShellCompactRailWidth = 56;

/// Extended rail / branded sidebar width target on desktop.
const double kDesktopSidebarWidth = 240;

enum HexaViewportClass {
  compactPhone,
  phone,
  tablet,
  desktop,
  ultraWide,
}

/// Flutter-native responsive primitives for Harisree app surfaces.
///
/// Keep page-specific layout choices local, but route all breakpoints, gutters,
/// sheet constraints, and touch-target minimums through this file.
abstract final class HexaBreakpoints {
  const HexaBreakpoints._();

  static const double compactPhone = 360;
  static const double phone = 600;
  static const double tablet = 900;
  static const double desktop = 1100;
  static const double ultraWide = 1600;

  /// Layout width; 0 when MediaQuery is not ready (web first frame).
  static double _layoutWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (!w.isFinite || w <= 0) return 0;
    return w;
  }

  static HexaViewportClass classify(double width) {
    if (!width.isFinite || width <= 0) return HexaViewportClass.phone;
    if (width < compactPhone) return HexaViewportClass.compactPhone;
    if (width < phone) return HexaViewportClass.phone;
    if (width < tablet) return HexaViewportClass.tablet;
    if (width < ultraWide) return HexaViewportClass.desktop;
    return HexaViewportClass.ultraWide;
  }

  static bool isCompact(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w < compactPhone;
  }

  static bool isPhone(BuildContext context) {
    final w = _layoutWidth(context);
    return w == 0 || w < phone;
  }

  static bool isTabletOrLarger(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= tablet;
  }

  static bool isDesktop(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= desktop;
  }

  /// Master-detail and desktop dashboard grids (spec: ≥1024).
  static bool isDesktopLayout(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= kDesktopMin;
  }

  static bool isNavigationRail(BuildContext context) {
    final w = _layoutWidth(context);
    return w > 0 && w >= kNavigationRailMin;
  }
}

double _hexaLayoutWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (!w.isFinite || w <= 0) return 0;
  return w;
}

/// Layout helpers aligned to DESKTOP_DESIGN_SPEC breakpoints.
extension HexaLayoutContext on BuildContext {
  bool get isMobileLayout {
    final w = _hexaLayoutWidth(this);
    return w == 0 || w <= kMobileMax;
  }

  bool get isTabletLayout {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kTabletMin && w < kDesktopMin;
  }

  bool get isDesktopLayout {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kDesktopMin;
  }

  bool get showsNavigationRail {
    final w = _hexaLayoutWidth(this);
    return w > 0 && w >= kNavigationRailMin;
  }
}

abstract final class HexaResponsive {
  const HexaResponsive._();

  static const double minTouchTarget = 48;
  static const double minReadableFont = 11;
  static const double maxContentWidth = 1180;
  static const double maxFormWidth = 720;
  static const double maxSheetWidth = 640;

  /// Vertical gap between home/report sections (tighter on phones).
  static double sectionGap(BuildContext context) {
    final width = _hexaLayoutWidth(context);
    if (width == 0 || width <= kMobileMax) return HexaOp.mobileSectionGap;
    if (width < kDesktopMin) return HexaOp.sectionGap;
    return HexaOp.desktopSectionGap;
  }

  static double pageGutter(
    BuildContext context, {
    bool operational = false,
  }) {
    final width = _hexaLayoutWidth(context);
    if (width == 0 || width < HexaBreakpoints.compactPhone) return 12;
    if (operational) {
      if (width >= HexaBreakpoints.desktop) return 20;
      return HexaOp.pageGutter;
    }
    if (width >= HexaBreakpoints.desktop) return 32;
    if (width >= HexaBreakpoints.tablet) return 24;
    return 16;
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    bool operational = false,
    double top = 8,
    double bottom = 24,
  }) {
    final gutter = pageGutter(context, operational: operational);
    return EdgeInsets.fromLTRB(gutter, top, gutter, bottom);
  }

  static double clampedFont(double value) => math.max(minReadableFont, value);

  static double adaptiveSheetMaxHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final ratio = landscape ? 0.92 : 0.86;
    return math.max(280, size.height * ratio);
  }
}

class HexaResponsiveCenter extends StatelessWidget {
  const HexaResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = HexaResponsive.maxContentWidth,
    this.padding,
    this.alignTop = true,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignTop ? Alignment.topCenter : Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? HexaResponsive.pagePadding(context),
          child: child,
        ),
      ),
    );
  }
}

class HexaResponsiveSheetViewport extends StatelessWidget {
  const HexaResponsiveSheetViewport({
    super.key,
    required this.child,
    this.maxWidth = HexaResponsive.maxSheetWidth,
    this.padding,
    this.bottomExtra = 16,
    this.scrollController,
    this.compact = false,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final double bottomExtra;
  final ScrollController? scrollController;
  /// When true, sheet height hugs content (action menus). Avoids full-screen white gap.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          HexaResponsive.pageGutter(context, operational: true),
          compact ? 8 : 4,
          HexaResponsive.pageGutter(context, operational: true),
          bottomExtra + bottomSafe,
        );

    final padded = Padding(padding: effectivePadding, child: child);

    if (compact) {
      return AnimatedPadding(
        duration: HexaDsMotion.fast,
        curve: HexaDsMotion.enter,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: padded,
            ),
          ),
        ),
      );
    }

    return AnimatedPadding(
      duration: HexaDsMotion.fast,
      curve: HexaDsMotion.enter,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: HexaResponsive.adaptiveSheetMaxHeight(context),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: effectivePadding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard bottom sheet host — compact sheets hug content (no top blank gap).
Future<T?> showHexaBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool compact = true,
  EdgeInsetsGeometry? padding,
  double maxWidth = HexaResponsive.maxSheetWidth,
  ShapeBorder? shape,
}) {
  if (HexaBreakpoints.isDesktop(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 240, vertical: 80),
        shape: shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
    builder: (ctx) => HexaResponsiveSheetViewport(
      compact: compact,
      padding: padding,
      maxWidth: maxWidth,
      child: child,
    ),
  );
}

class HexaAccessibleFilterChip extends StatelessWidget {
  const HexaAccessibleFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: HexaResponsive.minTouchTarget),
      child: FilterChip(
        label: Text(
          label,
          style: HexaDsType.label(compact ? 11 : 12).copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        onSelected: onSelected,
      ),
    );
  }
}
