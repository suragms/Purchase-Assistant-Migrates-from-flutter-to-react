import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hexa_colors.dart';
import '../presentation/widgets/reports_period_bar.dart';

/// Reports header: back, title, search, period icons, filter, export.
class ReportsTopBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  const ReportsTopBar({
    super.key,
    required this.onBack,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilter,
    this.filterCount = 0,
    required this.onExport,
    this.exporting = false,
    this.selectedPeriodPreset,
    this.onPeriodPresetSelected,
    this.onCustomPeriod,
    this.onSyncHomePeriod,
    this.showPeriodRow = true,
  });

  final VoidCallback onBack;
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onFilter;
  final int filterCount;
  final VoidCallback onExport;
  final bool exporting;
  final String? selectedPeriodPreset;
  final ValueChanged<String>? onPeriodPresetSelected;
  final VoidCallback? onCustomPeriod;
  final VoidCallback? onSyncHomePeriod;
  final bool showPeriodRow;

  @override
  ConsumerState<ReportsTopBar> createState() => _ReportsTopBarState();

  @override
  Size get preferredSize {
    final periodExtra = showPeriodRow && selectedPeriodPreset != null ? 44.0 : 0.0;
    return Size.fromHeight(104 + periodExtra);
  }
}

class _ReportsTopBarState extends ConsumerState<ReportsTopBar> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchTextChanged);
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showPeriod = widget.showPeriodRow &&
        widget.selectedPeriodPreset != null &&
        widget.onPeriodPresetSelected != null &&
        widget.onCustomPeriod != null;

    return Material(
      color: HexaColors.brandBackground,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    onPressed: widget.onBack,
                    visualDensity: VisualDensity.compact,
                  ),
                  const Expanded(
                    child: Text(
                      'Reports',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'Filters',
                        icon: const Icon(Icons.tune_rounded, size: 22),
                        onPressed: widget.onFilter,
                        visualDensity: VisualDensity.compact,
                      ),
                      if (widget.filterCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: HexaColors.brandPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${widget.filterCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Export',
                    onPressed: widget.exporting ? null : widget.onExport,
                    visualDensity: VisualDensity.compact,
                    icon: widget.exporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 22),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: widget.searchController,
                  onChanged: widget.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: widget.searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: widget.onClearSearch,
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: HexaColors.brandCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              if (showPeriod) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ReportsPeriodIconRow(
                    selectedPreset: widget.selectedPeriodPreset!,
                    onPresetSelected: widget.onPeriodPresetSelected!,
                    onCustomRange: widget.onCustomPeriod!,
                    onSyncHome: widget.onSyncHomePeriod,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
