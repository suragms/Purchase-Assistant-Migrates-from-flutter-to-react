import 'package:flutter/material.dart';

/// Tab bodies inside [CustomScrollView] must not use independent scrollables.
/// Use this wrapper for list-like tab content (shrink-wrapped, non-scrollable).
Widget reportsNestedListBody({required List<Widget> children}) {
  return ListView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    children: children,
  );
}
