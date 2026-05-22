import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Collapsible operational section — 52dp collapsed header.
class HomeCollapsibleSection extends StatefulWidget {
  const HomeCollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool initiallyExpanded;

  @override
  State<HomeCollapsibleSection> createState() => _HomeCollapsibleSectionState();
}

class _HomeCollapsibleSectionState extends State<HomeCollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: HexaOp.collapsedHeader,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: HexaDsType.heading(
                          14,
                          color: HexaDsColors.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: HexaDsColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
