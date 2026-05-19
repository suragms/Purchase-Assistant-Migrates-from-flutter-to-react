import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/barcode_recent_scans.dart';
import '../../../core/router/navigation_ext.dart';

const _kMaxRecent = 10;
const _kDebounceMs = 1500;

/// Warehouse barcode scan — camera + manual lookup → item detail.
class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _camera;
  final _manualCtrl = TextEditingController();
  bool _torch = false;
  bool _busy = false;
  String? _lastCode;
  DateTime? _lastAt;
  List<BarcodeRecentScan> _recent = [];
  late final AnimationController _scanLineCtrl;

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    unawaited(_loadRecent());
    if (!kIsWeb) {
      _camera = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: const [BarcodeFormat.code128, BarcodeFormat.qrCode],
      );
    }
  }

  Future<void> _loadRecent() async {
    final list = await loadBarcodeRecentScans(max: _kMaxRecent);
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _pushRecent(BarcodeRecentScan row) async {
    final next = <BarcodeRecentScan>[
      row,
      ..._recent.where((x) => x.code != row.code),
    ].take(_kMaxRecent).toList();
    setState(() => _recent = next);
    await saveBarcodeRecentScans(next);
  }

  bool _debouncePass(String code) {
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastAt != null &&
        now.difference(_lastAt!) <
            const Duration(milliseconds: _kDebounceMs)) {
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    return true;
  }

  Future<void> _resumeScan() async {
    if (!kIsWeb && _camera != null) {
      try {
        await _camera!.start();
      } catch (_) {}
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _showNotFoundSheet(String code) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Item not found',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Code: $code',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/catalog/quick-add?itemCode=${Uri.encodeComponent(code)}&source=scan',
                  );
                },
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create new item'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_resumeScan());
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan again'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
    await _resumeScan();
  }

  Future<void> _lookupAndNavigate(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (_busy) return;
    if (!kIsWeb) {
      try {
        await _camera?.stop();
      } catch (_) {}
    }
    setState(() => _busy = true);
    try {
      final row = await ref.read(hexaApiProvider).barcodeStockLookup(
            businessId: session.primaryBusiness.id,
            code: code,
          );
      final id = row['id']?.toString();
      final name = row['name']?.toString() ?? code;
      if (id == null || id.isEmpty) {
        await _showNotFoundSheet(code);
        return;
      }
      await _pushRecent(
        BarcodeRecentScan(id: id, name: name, code: code),
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      context.push('/catalog/item/$id?source=scan');
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        await _showNotFoundSheet(code);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
      await _resumeScan();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture cap) {
    if (_busy) return;
    final first = cap.barcodes.isNotEmpty ? cap.barcodes.first : null;
    final v = first?.rawValue?.trim();
    if (v == null || v.isEmpty) return;
    if (!_debouncePass(v)) return;
    unawaited(_lookupAndNavigate(v));
  }

  Future<void> _toggleTorch() async {
    if (_camera == null) return;
    await _camera!.toggleTorch();
    setState(() => _torch = !_torch);
  }

  void _goBack(BuildContext context) {
    final p = GoRouterState.of(context).uri.path;
    if (p.startsWith('/staff')) {
      context.go('/staff/home');
    } else {
      context.popOrGo('/catalog');
    }
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _manualCtrl.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final cameraH = screenH * 0.65;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _goBack(context),
        ),
        title: const Text('Scan barcode'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'Torch',
              onPressed: _toggleTorch,
              icon: Icon(
                _torch
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Material(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Camera scan is not available in the browser. '
                          'Enter the item code below or open the app on your phone to scan.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: cameraH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _camera,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 280,
                      height: 160,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return AnimatedBuilder(
                        animation: _scanLineCtrl,
                        builder: (context, _) {
                          final y = 160 * _scanLineCtrl.value;
                          return Align(
                            alignment: Alignment.center,
                            child: Transform.translate(
                              offset: Offset(0, y - 80),
                              child: Container(
                                width: 260,
                                height: 2,
                                color: Colors.redAccent,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const Align(
                    alignment: Alignment(0, 0.72),
                    child: Text(
                      'Align barcode within the frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 6,
                            color: Color(0xAA000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          if (_recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Recent scans',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final r = _recent[i];
                  final label = r.name.length > 15
                      ? '${r.name.substring(0, 15)}…'
                      : r.name;
                  return ActionChip(
                    label: Text(label, maxLines: 1),
                    onPressed: _busy
                        ? null
                        : () {
                            if (r.id.isNotEmpty) {
                              context.push('/catalog/item/${r.id}?source=scan');
                            } else {
                              _manualCtrl.text = r.code;
                              unawaited(_lookupAndNavigate(r.code));
                            }
                          },
                  );
                },
              ),
            ),
          ],
          Expanded(
            child: Material(
              elevation: 6,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Manual entry',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'Enter item code (e.g. ITM1022)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: _lookupAndNavigate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _lookupAndNavigate(_manualCtrl.text),
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
