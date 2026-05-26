import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hexa_ds_tokens.dart';
import 'hexa_operational_tokens.dart';

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

  static HexaViewportClass classify(double width) {
    if (width < compactPhone) return HexaViewportClass.compactPhone;
    if (width < phone) return HexaViewportClass.phone;
    if (width < tablet) return HexaViewportClass.tablet;
    if (width < ultraWide) return HexaViewportClass.desktop;
    return HexaViewportClass.ultraWide;
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactPhone;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phone;

  static bool isTabletOrLarger(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}

abstract final class HexaResponsive {
  const HexaResponsive._();

  static const double minTouchTarget = 48;
  static const double minReadableFont = 11;
  static const double maxContentWidth = 1180;
  static const double maxFormWidth = 720;
  static const double maxSheetWidth = 640;

  static double pageGutter(
    BuildContext context, {
    bool operational = false,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < HexaBreakpoints.compactPhone) return 12;
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
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final double bottomExtra;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          HexaResponsive.pageGutter(context, operational: true),
          8,
          HexaResponsive.pageGutter(context, operational: true),
          bottomExtra + bottomSafe,
        );

    return AnimatedPadding(
      duration: HexaDsMotion.fast,
      curve: HexaDsMotion.enter,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
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
