import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Lightweight, const-friendly placeholder blocks used while a provider is
/// resolving. Keeps the scaffold/appbar/tabs mounted so pages feel instant
/// to open — replaces full-screen [CircularProgressIndicator] pages.
///
/// All children are `const` and dimensionally cheap; no animations, no
/// shimmer package. The goal is "page is clearly there, content arriving",
/// not a pretty shimmer.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.radius = 10});
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F1),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for vertical list pages (history, contacts, ledger, etc).
/// Renders [rowCount] placeholder cards with safe default height.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.rowCount = 6,
    this.rowHeight = 84,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 100),
    this.shimmer = true,
  });

  final int rowCount;
  final double rowHeight;
  final EdgeInsets padding;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: rowCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => _SkeletonBox(height: rowHeight, radius: 12),
    );
    if (!shimmer) return list;
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: list,
    );
  }
}

/// Skeleton for entity detail pages (purchase / supplier / broker / item).
/// Shows a hero card + two meta cards so the user sees structure immediately.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: const [
        _SkeletonBox(height: 128, radius: 14),
        SizedBox(height: 12),
        _SkeletonBox(height: 160, radius: 14),
        SizedBox(height: 12),
        _SkeletonBox(height: 96, radius: 14),
      ],
    );
  }
}
