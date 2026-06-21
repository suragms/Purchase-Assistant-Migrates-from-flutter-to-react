import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/resolve_catalog_item_id.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Resolves item name → catalog detail.
class ItemAnalyticsRedirectPage extends ConsumerStatefulWidget {
  const ItemAnalyticsRedirectPage({super.key, required this.itemName});

  final String itemName;

  @override
  ConsumerState<ItemAnalyticsRedirectPage> createState() =>
      _ItemAnalyticsRedirectPageState();
}

class _ItemAnalyticsRedirectPageState
    extends ConsumerState<ItemAnalyticsRedirectPage> {
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    if (_resolved) return;
    final id = await resolveCatalogItemId(
      ref,
      itemName: widget.itemName,
    );
    if (!mounted) return;
    _resolved = true;
    if (id != null && id.isNotEmpty) {
      final tab = GoRouterState.of(context).uri.queryParameters['tab'];
      final q = tab != null && tab.isNotEmpty ? '?tab=$tab' : '?tab=analytics';
      context.go('/catalog/item/$id$q');
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.itemName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FriendlyLoadError(
            message:
                'This item is not linked to the catalog yet. Open Catalog to create or link it.',
            onRetry: () {
              _resolved = false;
              _redirect();
            },
          ),
        ],
      ),
    );
  }
}
