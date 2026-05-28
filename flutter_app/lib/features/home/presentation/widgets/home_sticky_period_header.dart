import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';
import 'home_period_filter_row.dart';

/// Sticky period chips for owner dashboard scroll.
class HomeStickyPeriodHeader extends SliverPersistentHeaderDelegate {
  HomeStickyPeriodHeader();

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: HexaColors.brandBackground,
      elevation: overlapsContent ? 1 : 0,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(0, 6, 0, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomePeriodFilterRow(),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                'Applies to purchase center and warehouse activity',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HomeStickyPeriodHeader oldDelegate) => false;
}
