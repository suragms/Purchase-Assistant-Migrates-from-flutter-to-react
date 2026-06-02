import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import 'public_item_scan_page.dart';

/// Public lookup page for external barcode scans: `/lookup?barcode=X&business=Y`.
class PublicBarcodeLookupPage extends StatefulWidget {
  const PublicBarcodeLookupPage({
    super.key,
    required this.barcode,
    required this.businessSlug,
  });

  final String barcode;
  final String businessSlug;

  @override
  State<PublicBarcodeLookupPage> createState() => _PublicBarcodeLookupPageState();
}

class _PublicBarcodeLookupPageState extends State<PublicBarcodeLookupPage> {
  late final Future<Map<String, dynamic>> _load;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.resolvedApiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final res = await dio.get<Map<String, dynamic>>(
      '/public/items/lookup',
      queryParameters: {
        'barcode': widget.barcode.trim(),
        'business': widget.businessSlug.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.barcode.trim();
    final biz = widget.businessSlug.trim();
    if (b.isEmpty || biz.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Barcode and business are required')),
      );
    }
    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _load,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: ListSkeleton(rowCount: 5, rowHeight: 72),
            );
          }
          if (snap.hasError) {
            return FriendlyLoadError(
              message: 'Item not found',
              onRetry: () => setState(() => _load = _fetch()),
            );
          }
          return PublicItemScanPage(lookupKey: b);
        },
      ),
    );
  }
}
