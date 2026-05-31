import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
import '../../reports/reports_bi_tab.dart';
import 'reports_layout.dart';

/// 56px compact reports header: back · title · actions.
class ReportsCompactHeader extends StatelessWidget implements PreferredSizeWidget {
  const ReportsCompactHeader({
    super.key,
    required this.tab,
    required this.onBack,
    required this.onSearch,
    required this.onFilter,
    this.filterCount = 0,
    required this.onExportPdf,
    required this.onShare,
    required this.onMore,
    this.exportingPdf = false,
  });

  final ReportsBiTab tab;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final int filterCount;
  final VoidCallback onExportPdf;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final bool exportingPdf;

  @override
  Size get preferredSize => const Size.fromHeight(kReportsHeaderHeight);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HexaColors.brandBackground,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kReportsHeaderHeight,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1,
                      ),
                    ),
                    Text(
                      tab.shortLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded, size: 22),
                onPressed: onSearch,
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Filters',
                    icon: const Icon(Icons.tune_rounded, size: 22),
                    onPressed: onFilter,
                  ),
                  if (filterCount > 0)
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
                          '$filterCount',
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
                tooltip: 'Export PDF',
                icon: exportingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 22),
                onPressed: onExportPdf,
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share_rounded, size: 22),
                onPressed: onShare,
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, size: 22),
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
