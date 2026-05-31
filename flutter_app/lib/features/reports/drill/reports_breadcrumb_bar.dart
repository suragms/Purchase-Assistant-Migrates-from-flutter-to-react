import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/hexa_colors.dart';

/// Breadcrumb trail for report drill-down pages.
class ReportsBreadcrumbBar extends StatelessWidget {
  const ReportsBreadcrumbBar({
    super.key,
    required this.segments,
  });

  /// Each segment: (label, optional route). Last segment has null route.
  final List<(String label, String? route)> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right_rounded,
                    size: 16, color: Color(0xFF94A3B8)),
              ),
            _Crumb(
              label: segments[i].$1,
              onTap: segments[i].$2 == null
                  ? null
                  : () => _navigateCrumb(context, segments[i].$2!),
              isLast: i == segments.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

/// Prefer pop when drill was pushed; otherwise go to the crumb route.
void _navigateCrumb(BuildContext context, String route) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(route);
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.onTap,
    required this.isLast,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: isLast ? FontWeight.w900 : FontWeight.w700,
      color: isLast ? HexaColors.brandPrimary : const Color(0xFF64748B),
    );
    if (onTap == null) {
      return Text(label, style: style);
    }
    return InkWell(
      onTap: onTap,
      child: Text(label, style: style),
    );
  }
}
