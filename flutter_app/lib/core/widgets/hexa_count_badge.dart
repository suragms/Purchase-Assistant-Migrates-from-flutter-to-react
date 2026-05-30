import 'package:flutter/material.dart';

/// Badge with optional count — [label] is always safe (Flutter builds it even when hidden).
class HexaCountBadge extends StatelessWidget {
  const HexaCountBadge({
    super.key,
    required this.child,
    this.count,
    this.maxDisplay = 99,
    this.backgroundColor,
  });

  final Widget child;
  final int? count;
  final int maxDisplay;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final n = count ?? 0;
    final show = n > 0;
    final label = show ? (n > maxDisplay ? '$maxDisplay+' : '$n') : '';
    return Badge(
      isLabelVisible: show,
      backgroundColor: backgroundColor,
      label: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
      child: child,
    );
  }
}
