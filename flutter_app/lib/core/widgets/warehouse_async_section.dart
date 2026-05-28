import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'friendly_load_error.dart';
import 'list_skeleton.dart';
import 'section_inline_error.dart';

/// Standard loading / error / data wrapper for warehouse sections.
class WarehouseAsyncSection<T> extends StatelessWidget {
  const WarehouseAsyncSection({
    super.key,
    required this.asyncValue,
    required this.dataBuilder,
    this.onRetry,
    this.loading,
    this.errorMessage = 'Unable to load data',
    this.offline = false,
    this.showCachedHint = false,
    this.denseError = false,
  });

  final AsyncValue<T> asyncValue;
  final Widget Function(T data) dataBuilder;
  final VoidCallback? onRetry;
  final Widget? loading;
  final String errorMessage;
  final bool offline;
  final bool showCachedHint;
  final bool denseError;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      loading: () => loading ?? const ListSkeleton(rowCount: 3, rowHeight: 72),
      error: (_, __) => denseError
          ? SectionInlineError(
              message: errorMessage,
              onRetry: onRetry ?? () {},
            )
          : FriendlyLoadError(
              message: errorMessage,
              subtitle: offline
                  ? 'You are offline. Showing cached data where available.'
                  : kFriendlyLoadNetworkSubtitle,
              onRetry: onRetry ?? () {},
            ),
      data: (data) {
        if (showCachedHint && offline) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CachedBanner(),
              dataBuilder(data),
            ],
          );
        }
        return dataBuilder(data);
      },
    );
  }
}

class _CachedBanner extends StatelessWidget {
  const _CachedBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Offline — cached snapshot',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF757575),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
