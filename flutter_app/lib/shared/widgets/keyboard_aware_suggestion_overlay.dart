import 'package:flutter/material.dart';

/// Overlay suggestions anchored to the target field ([LayerLink]) so they paint
/// above wizard fields and the keyboard instead of behind sibling inputs.
class KeyboardAwareSuggestionOverlay extends StatefulWidget {
  const KeyboardAwareSuggestionOverlay({
    super.key,
    required this.controller,
    required this.child,
    required this.overlayChild,
  });

  final OverlayPortalController controller;
  final Widget child;
  final Widget overlayChild;

  @override
  State<KeyboardAwareSuggestionOverlay> createState() =>
      _KeyboardAwareSuggestionOverlayState();
}

class _KeyboardAwareSuggestionOverlayState
    extends State<KeyboardAwareSuggestionOverlay> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: widget.controller,
      overlayChildBuilder: (context) {
        final media = MediaQuery.of(context);
        final keyboardInset = media.viewInsets.bottom;
        final screenHeight = media.size.height;
        final visibleHeight = screenHeight - keyboardInset;

        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          return const SizedBox.shrink();
        }

        final size = box.size;
        final fieldOffset = box.localToGlobal(Offset.zero);
        final fieldBottom = fieldOffset.dy + size.height;

        const overlayHeight = 240.0;
        const gap = 8.0;

        final showAbove = fieldBottom > visibleHeight * 0.55 ||
            (fieldBottom + gap + overlayHeight > visibleHeight - gap);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.controller.hide,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor:
                  showAbove ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor:
                  showAbove ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, showAbove ? -gap : gap),
              child: Material(
                elevation: 12,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width,
                    maxHeight: overlayHeight,
                  ),
                  child: widget.overlayChild,
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: KeyedSubtree(
          key: _fieldKey,
          child: widget.child,
        ),
      ),
    );
  }
}
