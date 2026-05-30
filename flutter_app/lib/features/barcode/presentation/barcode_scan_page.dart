import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/providers/barcode_recent_scans.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/stock_audit_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/stock_offline_queue_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../shared/widgets/search_picker_sheet.dart';
import '../../stock/presentation/quick_stock_action_sheet.dart';
import '../../stock/presentation/stock_undo_snackbar.dart';
import 'warehouse_scan_action_sheet.dart';
import 'barcode_scan_web_stub.dart'
    if (dart.library.html) 'barcode_scan_web.dart';

const _kMaxRecent = 10;
const _kDebounceMs = 1200;
const _kManualSearchDebounceMs = 400;
/// Retail + warehouse linear formats (fewer = faster camera decode).
const _kWarehouseBarcodeFormats = <BarcodeFormat>[
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.qrCode,
];

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
  final _manualFocus = FocusNode();
  String _manualQuery = '';
  bool _torch = false;
  bool _busy = false;
  String? _lastCode;
  DateTime? _lastAt;
  List<BarcodeRecentScan> _recent = [];
  List<Map<String, dynamic>> _manualMatches = const [];
  bool _manualSearching = false;
  Timer? _manualSearchDebounce;
  late final AnimationController _scanLineCtrl;
  bool _cameraDenied = false;
  bool _cameraPermanent = false;

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _manualCtrl.addListener(_onManualChanged);
    unawaited(_loadRecent());
    unawaited(_initCamera());
  }

  void _onManualChanged() {
    final next = _manualCtrl.text.toLowerCase().trim();
    if (next == _manualQuery) return;
    setState(() {
      _manualQuery = next;
      if (next.length < 2) {
        _manualMatches = const [];
        _manualSearching = false;
      }
    });
    _manualSearchDebounce?.cancel();
    if (next.length < 2) return;
    _manualSearchDebounce = Timer(
      const Duration(milliseconds: _kManualSearchDebounceMs),
      () => unawaited(_searchManualItems(next)),
    );
  }

  Future<void> _searchManualItems(String q) async {
    final session = ref.read(sessionProvider);
    if (session == null || !mounted) return;
    setState(() => _manualSearching = true);
    try {
      final blob = await ref.read(hexaApiProvider).listStock(
            businessId: session.primaryBusiness.id,
            q: q,
            perPage: 8,
            page: 1,
          );
      if (!mounted || _manualQuery != q) return;
      final items = [
        for (final row in (blob['items'] as List? ?? []))
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      setState(() {
        _manualMatches = items;
        _manualSearching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _manualMatches = const [];
          _manualSearching = false;
        });
      }
    }
  }

  Future<void> _scanFromImage() async {
    if (_busy) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    String? code;
    try {
      if (_camera != null) {
        final cap = await _camera!.analyzeImage(file.path);
        if (cap != null && cap.barcodes.isNotEmpty) {
          code = cap.barcodes.first.rawValue?.trim();
        }
      }
      if ((code == null || code.isEmpty) && kIsWeb) {
        final bytes = await file.readAsBytes();
        code = await decodeBarcodeFromImageBytes(bytes);
      }
    } catch (_) {}
    if (code != null && code.isNotEmpty) {
      await _lookupAndNavigate(code);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Barcode image unreadable. Try another photo.'),
          action: SnackBarAction(
            label: 'Manual',
            onPressed: () => _manualFocus.requestFocus(),
          ),
        ),
      );
    }
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      try {
        _camera = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          detectionTimeoutMs: _kDebounceMs,
          facing: CameraFacing.back,
          formats: _kWarehouseBarcodeFormats,
        );
        if (mounted) setState(() {});
        return;
      } catch (_) {
        if (mounted) setState(() => _cameraDenied = true);
        return;
      }
    }
    final status = await Permission.camera.status;
    if (status.isDenied) {
      final req = await Permission.camera.request();
      if (!req.isGranted) {
        if (mounted) {
          setState(() {
            _cameraDenied = true;
            _cameraPermanent = req.isPermanentlyDenied;
          });
        }
        return;
      }
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _cameraDenied = true;
          _cameraPermanent = true;
        });
      }
      return;
    }
    if (!mounted) return;
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: _kDebounceMs,
      facing: CameraFacing.back,
      formats: _kWarehouseBarcodeFormats,
    );
    setState(() {});
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
        now.difference(_lastAt!) < const Duration(milliseconds: _kDebounceMs)) {
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    return true;
  }

  Future<void> _resumeScan() async {
    _busy = false;
    if (!kIsWeb && _camera != null) {
      try {
        await _camera!.start();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _assignBarcodeToExisting(String code) async {
    final session = ref.read(sessionProvider);
    if (session == null || !mounted) return;
    final catalog = ref.read(catalogItemsListProvider).valueOrNull ?? [];
    if (catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load catalog first, then try again')),
      );
      await _resumeScan();
      return;
    }
    final picked = await showSearchPickerSheet<String>(
      context: context,
      title: 'Assign barcode $code',
      rows: [
        for (final row in catalog)
          SearchPickerRow<String>(
            value: row['id']?.toString() ?? '',
            title: row['name']?.toString() ?? '—',
            subtitle: row['item_code']?.toString(),
          ),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) {
      await _resumeScan();
      return;
    }
    try {
      await ref.read(hexaApiProvider).patchCatalogItemBarcode(
            businessId: session.primaryBusiness.id,
            itemId: picked,
            barcode: code,
          );
      ref.invalidate(catalogItemsListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode $code assigned')),
      );
      context.push('/catalog/item/$picked?source=scan');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(barcodeMessageForUser(e,
                ctx: BarcodeOperationContext.scanner))),
      );
      await _resumeScan();
    }
  }

  Future<void> _showFoundActions(
    Map<String, dynamic> row,
    String id,
    String name,
  ) async {
    if (!mounted) return;
    final returnTo = GoRouterState.of(context).uri.queryParameters['return'];
    if (returnTo == 'search') {
      if (mounted) context.pop(Map<String, dynamic>.from(row));
      return;
    }
    final saved = await showWarehouseScanActionSheet(
      context: context,
      ref: ref,
      item: Map<String, dynamic>.from(row),
    );
    if (saved && mounted) {
      ref.invalidate(stockListProvider);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(catalogItemDetailProvider(id));
      ref.invalidate(stockItemIntelligenceProvider(id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan update saved')),
      );
    }
    await _resumeScan();
  }

  Future<void> _showNotFoundSheet(String code) async {
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    final canEdit =
        session != null && !sessionIsStockReadOnly(session);
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
                'Unknown barcode',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Scanned: $code\nNot linked to any item in this business.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (!canEdit) ...[
                const SizedBox(height: 12),
                Text(
                  'Read-only account — ask owner/manager to assign this barcode.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              if (canEdit) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push(
                      '/catalog/quick-add-from-scan?barcode=${Uri.encodeComponent(code)}',
                    );
                  },
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Create new item'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_assignBarcodeToExisting(code));
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Assign to existing item'),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _manualFocus.requestFocus();
                },
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter manually'),
              ),
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
    if (!_busy) {
      _busy = true;
      if (mounted) setState(() {});
    }
    try {
      if (_camera != null) {
        try {
          await _camera!.stop();
        } catch (_) {}
      }
      final row = await ref
          .read(hexaApiProvider)
          .barcodeStockLookup(
            businessId: session.primaryBusiness.id,
            code: code,
          )
          .timeout(const Duration(seconds: 6));
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
      final returnTo = GoRouterState.of(context).uri.queryParameters['return'];
      if (returnTo == 'stock') {
        final saved = await showQuickStockActionSheet(
          context: context,
          ref: ref,
          item: Map<String, dynamic>.from(row),
        );
        if (saved && mounted) {
          ref.invalidate(stockListProvider);
          ref.invalidate(stockAuditPeriodProvider);
          if (id.isNotEmpty) {
            ref.invalidate(catalogItemDetailProvider(id));
            ref.invalidate(stockItemIntelligenceProvider(id));
          }
          await _loadRecent();
          showStockUndoSnackBar(
            context: context,
            ref: ref,
            itemId: id,
            itemName: name,
          );
        }
        if (mounted) context.pop();
        return;
      }
      await _showFoundActions(row, id, name);
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server is slow — try again'),
        ),
      );
      await _resumeScan();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        await _showNotFoundSheet(code);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(barcodeMessageForUser(e,
                ctx: BarcodeOperationContext.scanner))),
      );
      await _resumeScan();
    }
  }

  void _onDetect(BarcodeCapture cap) {
    if (_busy) return;
    final first = cap.barcodes.isNotEmpty ? cap.barcodes.first : null;
    final v = first?.rawValue?.trim();
    if (v == null || v.isEmpty) return;
    if (!_debouncePass(v)) return;
    _busy = true;
    unawaited(_lookupAndNavigate(v));
  }

  Future<void> _toggleTorch() async {
    if (_camera == null) return;
    await _camera!.toggleTorch();
    setState(() => _torch = !_torch);
  }

  Future<void> _startAuditSession() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final existing = await ref.read(hexaApiProvider).getActiveStockAudit(
            businessId: session.primaryBusiness.id,
          );
      if (existing != null && existing['id'] != null) {
        if (!mounted) return;
        context.push('/barcode/audit-session');
        return;
      }
      await ref.read(hexaApiProvider).createStockAudit(
            businessId: session.primaryBusiness.id,
            notes: 'Mobile scan session',
          );
      ref.invalidate(activeStockAuditProvider);
      if (!mounted) return;
      context.push('/barcode/audit-session');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(barcodeMessageForUser(e,
                ctx: BarcodeOperationContext.scanner))),
      );
    }
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
    _manualSearchDebounce?.cancel();
    _scanLineCtrl.dispose();
    _manualCtrl.removeListener(_onManualChanged);
    _manualCtrl.dispose();
    _manualFocus.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final cameraH = (size.height * (landscape ? 0.34 : 0.42))
        .clamp(landscape ? 150.0 : 220.0, landscape ? 240.0 : 380.0)
        .toDouble();
    final pendingSync = ref.watch(stockOfflinePendingCountProvider);
    final manualMatches = _manualMatches;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _goBack(context),
        ),
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Scan history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/barcode/scan-history'),
          ),
          IconButton(
            tooltip: 'Manual entry',
            icon: const Icon(Icons.keyboard_rounded),
            onPressed: () => _manualFocus.requestFocus(),
          ),
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
          IconButton(
            tooltip: 'Start audit session',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _busy ? null : () => unawaited(_startAuditSession()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendingSync > 0)
            MaterialBanner(
              content: Text('Pending sync: $pendingSync stock change(s)'),
              actions: [
                TextButton(
                  onPressed: () =>
                      ref.read(stockOfflineSyncProvider.notifier).syncNow(),
                  child: const Text('Sync now'),
                ),
              ],
            ),
          if (_cameraDenied)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.videocam_off_outlined,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    _cameraPermanent
                        ? 'Please allow camera access in Settings to scan barcodes.'
                        : 'Camera permission is needed to scan barcodes.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (_cameraPermanent)
                    FilledButton(
                      onPressed: openAppSettings,
                      child: const Text('Open Settings'),
                    )
                  else
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _cameraDenied = false;
                          _cameraPermanent = false;
                        });
                        unawaited(_initCamera());
                      },
                      child: const Text('Allow camera'),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Scanner unavailable on this device.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _FallbackAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan with camera',
                    onPressed: () {
                      setState(() {
                        _cameraDenied = false;
                        _cameraPermanent = false;
                      });
                      unawaited(_initCamera());
                    },
                  ),
                  _FallbackAction(
                    icon: Icons.photo_outlined,
                    label: 'Upload barcode photo',
                    onPressed: _busy ? null : _scanFromImage,
                  ),
                  _FallbackAction(
                    icon: Icons.keyboard,
                    label: 'Enter manually',
                    onPressed: () => _manualFocus.requestFocus(),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _cameraDenied = false;
                        _cameraPermanent = false;
                      });
                      unawaited(_initCamera());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: cameraH,
              child: ColoredBox(
                color: const Color(0xFFF1F5F9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_camera != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: MobileScanner(
                            controller: _camera,
                            onDetect: _onDetect,
                          ),
                        ),
                      )
                    else
                      const Center(child: CircularProgressIndicator()),
                    Center(
                      child: Container(
                        width: math.min(
                          260,
                          size.width -
                              HexaResponsive.pageGutter(
                                    context,
                                    operational: true,
                                  ) *
                                  2,
                        ),
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: HexaColors.brandPrimary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Align barcode here',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: HexaColors.brandPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                                  width: math.min(
                                    260,
                                    MediaQuery.sizeOf(context).width -
                                        HexaResponsive.pageGutter(
                                              context,
                                              operational: true,
                                            ) *
                                            2,
                                  ),
                                  height: 2,
                                  color: Colors.redAccent,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (_busy)
                      Container(
                        color: Colors.white54,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Scan item barcode or enter code manually.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          focusNode: _manualFocus,
                          controller: _manualCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: 'Search item / barcode / item code',
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
                  if (_manualSearching) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (manualMatches.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: manualMatches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final item = manualMatches[i];
                          final id = item['id']?.toString();
                          final name = item['name']?.toString() ?? 'Item';
                          final code = item['item_code']?.toString();
                          final barcode = item['barcode']?.toString();
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (code != null && code.isNotEmpty) code,
                                if (barcode != null && barcode.isNotEmpty)
                                  'Barcode $barcode',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: id == null || id.isEmpty
                                ? null
                                : () => context
                                    .push('/catalog/item/$id?source=scan'),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackAction extends StatelessWidget {
  const _FallbackAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        height: HexaOp.buttonHeight,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
