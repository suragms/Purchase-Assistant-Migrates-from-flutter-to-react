import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/form_field_scroll.dart';

/// A selectable option for [InlineSearchField].
class InlineSearchItem {
  const InlineSearchItem({
    required this.id,
    required this.label,
    this.subtitle,

    /// Lowercase-ish blob for matching (e.g. name + code + HSN). Display stays [label].
    this.searchText,

    /// Higher sorts earlier when match rank ties (e.g. supplier-linked catalog row).
    this.sortBoost = 0,

    /// Optional ERP metrics
    this.pendingBalance,
    this.lastPurchaseDate,
  });

  final String id;
  final String label;
  final String? subtitle;
  final String? searchText;
  final int sortBoost;

  final double? pendingBalance;
  final String? lastPurchaseDate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineSearchItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Inline search with [RawAutocomplete] overlay (max height 200, scrollable).
///
/// * Enter auto-picks when exactly one option matches the current query.
/// * Blur auto-picks when typed text matches exactly one item (case-insensitive).
class InlineSearchField extends StatefulWidget {
  const InlineSearchField({
    super.key,
    required this.items,
    required this.onSelected,
    this.controller,
    this.placeholder,
    this.initialLabel,
    this.prefixIcon,
    this.focusAfterSelection,
    this.textInputAction,
    this.focusNode,
    this.minQueryLength = 1,
  });

  final List<InlineSearchItem> items;
  final int minQueryLength;
  final void Function(InlineSearchItem item) onSelected;
  final TextEditingController? controller;
  final String? placeholder;
  final String? initialLabel;
  final Widget? prefixIcon;
  final FocusNode? focusAfterSelection;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  @override
  State<InlineSearchField> createState() => _InlineSearchFieldState();
}

class _InlineSearchFieldState extends State<InlineSearchField> {
  late final TextEditingController _ctrl = widget.controller ??
      TextEditingController(text: widget.initialLabel ?? '');
  late final FocusNode _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  bool get _disposeFocus => widget.focusNode == null;

  /// Same group as autocomplete options overlay so taps on suggestions are not "outside".
  final Object _suggestionTapGroup = Object();

  bool _pickInProgress = false;
  InlineSearchItem? _pendingSelection;
  String? _lastPickFingerprint;
  int _lastPickMs = 0;

  bool get _hasPendingSelection => _pendingSelection != null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (_disposeFocus) _ownedFocus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) return;
    if (_hasPendingSelection) {
      final pending = _pendingSelection!;
      _pendingSelection = null;
      _pick(pending, keepFocus: false);
      return;
    }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || _focus.hasFocus || _hasPendingSelection) return;
      setState(() {});
    });
    if (!_pickInProgress) {
      final q = _ctrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        final exact = <InlineSearchItem>[];
        for (final it in widget.items) {
          if (it.label.toLowerCase() == q) {
            exact.add(it);
            if (exact.length > 1) break;
          }
        }
        if (exact.length == 1) {
          _pick(exact.first, keepFocus: false);
          return;
        }
      }
    }
    if (mounted) setState(() {});
  }

  bool _consumeIfDuplicatePick(InlineSearchItem it) {
    final fp = '${it.id}\u241e${it.label}';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPickFingerprint == fp && now - _lastPickMs < 400) return true;
    _lastPickFingerprint = fp;
    _lastPickMs = now;
    return false;
  }

  int _matchRank(InlineSearchItem it, String q) {
    final lab = it.label.toLowerCase();
    final blob = (it.searchText ?? lab).toLowerCase();
    final sub = (it.subtitle ?? '').toLowerCase();
    if (lab == q) return 1000;
    if (lab.startsWith(q)) return 920;
    for (final token in blob.split(RegExp(r'\s+'))) {
      if (token == q) return 880;
      if (token.startsWith(q)) return 860;
    }
    if (lab.contains(q)) return 800;
    if (sub.contains(q)) return 720;
    if (blob.contains(q)) return 640;
    return 0;
  }

  Iterable<InlineSearchItem> _optionsForQuery(String raw) {
    final q = raw.trim().toLowerCase();
    final min = widget.minQueryLength.clamp(0, 64);
    if (q.isEmpty) {
      if (min > 0) return const [];
      final all = widget.items.toList();
      if (all.length <= 8) return all;
      return all.take(8);
    }
    if (q.length < min) return const [];
    final matched = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (_matchRank(it, q) > 0) matched.add(it);
    }
    matched.sort((a, b) {
      final ra = _matchRank(a, q);
      final rb = _matchRank(b, q);
      if (ra != rb) return rb.compareTo(ra);
      return b.sortBoost.compareTo(a.sortBoost);
    });
    if (matched.length <= 8) return matched;
    return matched.take(8);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final opts = _optionsForQuery(_ctrl.text).toList();
      if (opts.length == 1) {
        _pick(opts.first, keepFocus: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _pick(InlineSearchItem it, {bool keepFocus = true}) {
    if (_consumeIfDuplicatePick(it)) return;
    _pickInProgress = true;
    final label = it.label;
    _ctrl.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    if (!mounted) {
      _pickInProgress = false;
      return;
    }
    setState(() {});
    try {
      widget.onSelected(it);
      HapticFeedback.selectionClick();
    } finally {
      _pickInProgress = false;
    }
    final next = widget.focusAfterSelection;
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) next.requestFocus();
      });
    } else if (!keepFocus) {
      _focus.unfocus();
    }
  }

  double _optionsMaxHeight(BuildContext context, int optionCount) {
    final mq = MediaQuery.of(context);
    var usable = mq.size.height - mq.viewInsets.bottom - mq.padding.vertical;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      usable -= kMobileFormKeyboardAccessoryAllowance;
    }
    final byCount = optionCount * 56.0 + 48;
    final v = math.max(120.0, math.min(usable * 0.42, byCount));
    return math.min(200.0, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TapRegion(
      groupId: _suggestionTapGroup,
      onTapOutside: (_) {
        if (_pickInProgress) return;
        _focus.unfocus();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          RawAutocomplete<InlineSearchItem>(
            focusNode: _focus,
            textEditingController: _ctrl,
            displayStringForOption: (InlineSearchItem o) => o.label,
            optionsBuilder: (TextEditingValue tev) {
              return _optionsForQuery(tev.text);
            },
            onSelected: (InlineSearchItem it) => _pick(it, keepFocus: false),
            fieldViewBuilder: (
              BuildContext context,
              TextEditingController textEditingController,
              FocusNode focusNode,
              VoidCallback onFieldSubmitted,
            ) {
              return Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  textInputAction:
                      widget.textInputAction ?? TextInputAction.search,
                  onSubmitted: (_) {
                    final opts =
                        _optionsForQuery(textEditingController.text).toList();
                    if (opts.length == 1) {
                      _pick(opts.first, keepFocus: false);
                    } else {
                      onFieldSubmitted();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: widget.placeholder,
                    prefixIcon: widget.prefixIcon,
                    suffixIcon: textEditingController.text.isEmpty
                        ? const Icon(Icons.search_rounded, size: 22)
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              textEditingController.clear();
                              setState(() {});
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              );
            },
            optionsViewBuilder: (
              BuildContext context,
              AutocompleteOnSelected<InlineSearchItem> onSelected,
              Iterable<InlineSearchItem> options,
            ) {
              final opts = options.toList();
              if (opts.isEmpty) return const SizedBox.shrink();
              final mq = MediaQuery.of(context);
              final visibleHeight = mq.size.height - mq.viewInsets.bottom;
              final fieldBox =
                  _focus.context?.findRenderObject() as RenderBox?;
              final panelH = _optionsMaxHeight(context, opts.length);
              var lift = 0.0;
              if (fieldBox != null && fieldBox.hasSize) {
                final bottom =
                    fieldBox.localToGlobal(Offset.zero).dy + fieldBox.size.height;
                if (bottom > visibleHeight * 0.6 ||
                    bottom + panelH > visibleHeight - 8) {
                  lift = -(panelH + fieldBox.size.height + 8);
                }
              }
              return TapRegion(
                groupId: _suggestionTapGroup,
                child: Transform.translate(
                  offset: Offset(0, lift),
                  child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: _optionsMaxHeight(context, opts.length),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: 'Close suggestions',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                              onPressed: () => _focus.unfocus(),
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: ListView.separated(
                                shrinkWrap: false,
                                padding: EdgeInsets.zero,
                                physics: const ClampingScrollPhysics(),
                                itemCount: opts.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey[200],
                                ),
                                itemBuilder: (BuildContext ctx, int i) {
                                final it = opts[i];
                                void commit() {
                                  _pendingSelection = null;
                                  onSelected(it);
                                }

                                return GestureDetector(
                                  onTapDown: (_) => _pendingSelection = it,
                                  onTap: commit,
                                  behavior: HitTestBehavior.opaque,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 44,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            it.label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (it.subtitle != null &&
                                              it.subtitle!.trim().isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2),
                                              child: Text(
                                                it.subtitle!,
                                                maxLines: 3,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.25,
                                                  color: Color.lerp(
                                                    Theme.of(ctx)
                                                        .colorScheme
                                                        .onSurface,
                                                    Theme.of(ctx)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    0.35,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
