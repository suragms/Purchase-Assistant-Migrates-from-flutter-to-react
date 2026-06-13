import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../stock/presentation/stock_sheet_launch.dart';
import '../../stock/presentation/stock_undo_snackbar.dart';
import '../barcode_camera_session.dart';
import '../barcode_lookup_cache.dart';
import '../services/camera_permission_cache.dart';
import 'warehouse_scan_action_sheet.dart';
import 'barcode_scan_web_stub.dart'
    if (dart.library.html) 'barcode_scan_web.dart';
import 'web_live_barcode_scanner.dart' show WebLiveBarcodeScanner;

const _kMaxRecent = 10;
const _kDebounceMs = 200;
const _kCameraPermGrantedKey = 'camera_perm_granted';
const _kManualSearchDebounceMs = 400;
/// Primary warehouse formats (fewer = faster decode per frame).
const _kWarehouseBarcodeFormats = <BarcodeFormat>[
  BarcodeFormat.code128,
  BarcodeFormat.ean13,
  BarcodeFormat.qrCode,
];

/// Warehouse barcode scan — camera + manual lookup → item detail.
class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Avoid re-requesting OS camera permission on every scanner page open (iOS PWA).
  static bool _cameraPermissionGrantedThisSession = false;
  final _permCache = CameraPermissionCache.instance;

  MobileScannerController? _camera;
  WebLiveBarcodeScanner? _webLiveScanner;
  bool _useWebDetectorPreview = false;
  bool _cameraInitInFlight = false;
  String? _cameraDeniedMessage;
  final _manualCtrl = TextEditingController();
  final _manualFocus = FocusNode();
  String _manualQuery = '';
  bool _torch = false;
  bool _busy = false;
  int _scanGeneration = 0;
  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() {
      _busy = value;
    });
    if (value) {
      _scanLineCtrl.stop();
    } else {
      _scanLineCtrl.repeat(reverse: true);
    }
  }
  String? _lastCode;
  DateTime? _lastAt;
  List<BarcodeRecentScan> _recent = [];
  List<Map<String, dynamic>> _manualMatches = const [];
  bool _manualSearching = false;
  Timer? _manualSearchDebounce;
  late final AnimationController _scanLineCtrl;
  bool _cameraDenied = false;
  bool _cameraPermanent = false;
  Timer? _safariNoDetectTimer;
  bool _safariUploadNudgeShown = false;
  bool _hadDetectThisVisit = false;
  bool _scanConfirmed = false;
  String? _lookupLabel;
  bool _webCameraAwaitingGesture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true); // paused via _setBusy when camera is processing
    _manualCtrl.addListener(_onManualChanged);
    _manualFocus.addListener(_onManualFocusChange);
    unawaited(_loadRecent());
    unawaited(_bootstrapCamera());
  }

  Future<void> _bootstrapCamera() async {
    final persisted = await _readPersistedCameraPerm();
    _permCache.persistedGranted = persisted;
    if (persisted) {
      _cameraPermissionGrantedThisSession = true;
      _permCache.grantedThisSession = true;
    }
    if (kIsWeb && !_permCache.canAutoStartCamera) {
      if (mounted) setState(() => _webCameraAwaitingGesture = true);
      return;
    }
    await _initCamera();
  }

  Future<void> _startCameraFromUserGesture() async {
    if (mounted) setState(() => _webCameraAwaitingGesture = false);
    await _initCamera();
  }

  void _onManualFocusChange() {
    if (_manualFocus.hasFocus) {
      _scanLineCtrl.stop();
    } else if (!_busy) {
      _scanLineCtrl.repeat(reverse: true);
    }
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

  Future<bool> _readPersistedCameraPerm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCameraPermGrantedKey) ?? false;
  }

  Future<void> _markCameraPermGranted() async {
    _cameraPermissionGrantedThisSession = true;
    _permCache.markGranted();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCameraPermGrantedKey, true);
  }

  Future<void> _stopWebLiveScanner() async {
    await _webLiveScanner?.stop();
    _webLiveScanner = null;
    _useWebDetectorPreview = false;
  }

  MobileScannerController _newScannerController() {
    return MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: kIsWeb ? 400 : 100,
      facing: CameraFacing.back,
      formats: _kWarehouseBarcodeFormats,
      cameraResolution: const Size(1280, 720),
      autoStart: true,
      returnImage: false,
    );
  }

  void _flashScanConfirmed() {
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _scanConfirmed = true);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scanConfirmed = false);
    });
  }

  void _onWebBarcodeCode(String code) {
    if (_busy || !mounted) return;
    final v = code.trim();
    if (v.isEmpty) return;
    if (!_debouncePass(v)) return;
    _flashScanConfirmed();
    _hadDetectThisVisit = true;
    _safariNoDetectTimer?.cancel();
    unawaited(_lookupAndNavigate(v));
  }

  Future<bool> _tryStartWebBarcodeDetector() async {
    if (!kIsWeb) return false;
    final scanner = createWebLiveBarcodeScanner();
    if (scanner == null) return false;
    final ok = await scanner.start(_onWebBarcodeCode);
    if (!ok || !mounted) {
      await scanner.stop();
      return false;
    }
    await _camera?.dispose();
    _camera = null;
    BarcodeCameraSession.mobile = null;
    _webLiveScanner = scanner;
    _useWebDetectorPreview = true;
    BarcodeCameraSession.retainWebDetector(scanner);
    await _markCameraPermGranted();
    if (mounted) {
      setState(() {
        _cameraDenied = false;
        _cameraPermanent = false;
        _cameraDeniedMessage = null;
      });
      _scheduleSafariNoDetectNudge();
    }
    return true;
  }

  Future<void> _startWebMobileScanner() async {
    await _stopWebLiveScanner();
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS && _camera == null) {
        if (BarcodeCameraSession.mobile != null) {
          await BarcodeCameraSession.mobile!.dispose();
          BarcodeCameraSession.mobile = null;
        }
      }
      _camera = (defaultTargetPlatform == TargetPlatform.iOS)
          ? _newScannerController()
          : (BarcodeCameraSession.mobile ?? _newScannerController());
      BarcodeCameraSession.retainMobile(_camera!);
      await _markCameraPermGranted();
      if (mounted) {
        setState(() {
          _cameraDenied = false;
          _cameraPermanent = false;
          _cameraDeniedMessage = null;
        });
        _scheduleSafariNoDetectNudge();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraDenied = true;
          _cameraPermanent = false;
          _cameraDeniedMessage =
              'Could not start the camera in this browser. '
              'Allow camera for this site in Safari settings, or use '
              'Upload barcode photo / manual entry below.';
        });
      }
    }
  }

  Future<void> _startNativeMobileScanner() async {
    if (!mounted) return;
    _camera = BarcodeCameraSession.mobile ?? _newScannerController();
    BarcodeCameraSession.retainMobile(_camera!);
    if (!_camera!.value.isRunning) {
      await _camera!.start();
    }
    await _markCameraPermGranted();
    if (mounted) {
      setState(() {
        _cameraDenied = false;
        _cameraDeniedMessage = null;
      });
    }
  }

  void _scheduleSafariNoDetectNudge() {
    if (!kIsWeb || !isSafariBrowser) return;
    _safariNoDetectTimer?.cancel();
    _safariNoDetectTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          _busy ||
          _hadDetectThisVisit ||
          _safariUploadNudgeShown) {
        return;
      }
      setState(() => _safariUploadNudgeShown = true);
    });
  }

  Future<void> _retryCameraAfterDenial() async {
    await BarcodeCameraSession.reset();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    if ((_camera != null && _camera!.value.isRunning) ||
        (_useWebDetectorPreview && (_webLiveScanner?.isActive ?? false))) {
      return;
    }
    if (_cameraInitInFlight) return;
    _cameraInitInFlight = true;
    try {
      final persisted = await _readPersistedCameraPerm();
      if (persisted) {
        _cameraPermissionGrantedThisSession = true;
      }
      if (kIsWeb) {
        if (BarcodeCameraSession.hasLiveWebDetector &&
            BarcodeCameraSession.webDetector != null) {
          _webLiveScanner = BarcodeCameraSession.webDetector;
          _useWebDetectorPreview = true;
          await _webLiveScanner!.start(_onWebBarcodeCode);
          if (mounted) {
            setState(() {
              _cameraDenied = false;
              _cameraPermanent = false;
              _cameraDeniedMessage = null;
            });
          }
          return;
        }
        if (BarcodeCameraSession.hasLiveMobile &&
            BarcodeCameraSession.mobile != null) {
          final retained = BarcodeCameraSession.mobile!;
          var reuseOk = true;
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            reuseOk = false;
            await BarcodeCameraSession.reset();
          }
          if (reuseOk) {
            _camera = retained;
            if (mounted) {
              setState(() {
                _cameraDenied = false;
                _cameraPermanent = false;
                _cameraDeniedMessage = null;
              });
            }
            return;
          }
        }
        if (await _tryStartWebBarcodeDetector()) return;
        await _startWebMobileScanner();
        return;
      }

      final status = await Permission.camera.status;
      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _cameraDenied = true;
            _cameraPermanent = true;
            _cameraDeniedMessage = null;
          });
        }
        return;
      }

      if (status.isGranted || status.isLimited) {
        await _markCameraPermGranted();
        await _startNativeMobileScanner();
        return;
      }

      if (_cameraPermissionGrantedThisSession || persisted) {
        final recheck = await Permission.camera.status;
        if (recheck.isGranted || recheck.isLimited) {
          await _markCameraPermGranted();
          await _startNativeMobileScanner();
          return;
        }
        if (persisted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_kCameraPermGrantedKey, false);
        }
        _cameraPermissionGrantedThisSession = false;
      }

      final req = await Permission.camera.request();
      if (!req.isGranted && !req.isLimited) {
        if (mounted) {
          setState(() {
            _cameraDenied = true;
            _cameraPermanent = req.isPermanentlyDenied;
            _cameraDeniedMessage = null;
          });
        }
        return;
      }

      if (!mounted) return;
      await _markCameraPermGranted();
      await _startNativeMobileScanner();
    } finally {
      _cameraInitInFlight = false;
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
        now.difference(_lastAt!) < const Duration(milliseconds: _kDebounceMs)) {
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    return true;
  }

  Future<void> _resumeScan({int? generation}) async {
    if (generation != null && generation != _scanGeneration) return;
    if (!mounted) return;
    _setBusy(false);
    _lastCode = null;
    _lastAt = null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    if (generation != null && generation != _scanGeneration) return;

    if (_useWebDetectorPreview && _webLiveScanner != null) {
      // BarcodeDetector loop keeps running while _busy blocks new codes.
    } else if (_camera != null) {
      try {
        if (!_camera!.value.isInitialized) {
          await _initCamera();
        } else if (!kIsWeb &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            !_camera!.value.isRunning) {
          await _camera!.start();
        }
      } catch (_) {
        if (mounted) unawaited(_initCamera());
      }
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
    try {
      final saved = await showWarehouseScanActionSheet(
        context: context,
        ref: ref,
        item: Map<String, dynamic>.from(row),
      );
      if (saved && mounted) {
        ref.invalidate(catalogItemsListProvider);
        ref.invalidate(catalogItemDetailProvider(id));
        ref.invalidate(stockItemIntelligenceProvider(id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan update saved')),
        );
      }
    } finally {
      if (mounted) await _resumeScan();
    }
  }

  Future<void> _showNotFoundSheet(String code) async {
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    final canEdit =
        session != null && !sessionIsStockReadOnly(session);
    await showHexaBottomSheet<void>(
      context: context,
      compact: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Unknown barcode',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
              const SizedBox(height: 6),
              Text(
                'Scanned: $code\nNot linked to any item in this business.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (!canEdit) ...[
                const SizedBox(height: 12),
                Text(
                  'Read-only account — ask owner/manager to assign this barcode.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              if (canEdit) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
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
                    Navigator.pop(context);
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
                  Navigator.pop(context);
                  _manualFocus.requestFocus();
                },
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter manually'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_resumeScan());
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan again'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
      ),
    );
    await _resumeScan();
  }

  Future<void> _lookupAndNavigate(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _busy) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;

    final gen = ++_scanGeneration;
    _setBusy(true);
    if (mounted) setState(() => _lookupLabel = code);

    // Do NOT stop camera on iOS — just ignore new detects via _busy flag
    // Only stop on non-web (Android) where stop/start is reliable
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _camera?.stop();
      } catch (_) {}
    }

    try {
      final bid = session.primaryBusiness.id;
      var row = BarcodeLookupCache.get(bid, code);
      row ??= await ref
          .read(hexaApiProvider)
          .barcodeStockLookup(
            businessId: bid,
            code: code,
          )
          .timeout(const Duration(seconds: 6));
      BarcodeLookupCache.put(bid, code, row);
      final id = row['id']?.toString();
      final name = row['name']?.toString() ?? code;
      if (id == null || id.isEmpty) {
        await _showNotFoundSheet(code);
        return;
      }
      await _pushRecent(
        BarcodeRecentScan(id: id, name: name, code: code),
      );
      if (!mounted) return;
      final returnTo = GoRouterState.of(context).uri.queryParameters['return'];
      if (returnTo == 'stock') {
        final saved = await openQuickStockWithFreshItem(
          context: context,
          ref: ref,
          itemId: id,
          itemName: name,
          fallbackRow: Map<String, dynamic>.from(row),
          skipFreshFetch: true,
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
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Server is starting up. Please wait a moment and try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _lookupAndNavigate(raw),
          ),
        ),
      );
      await _resumeScan();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      if (e.response?.statusCode == 404) {
        await _showNotFoundSheet(code);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barcodeMessageForUser(e, ctx: BarcodeOperationContext.scanner),
          ),
        ),
      );
      await _resumeScan();
    } finally {
      if (mounted) {
        setState(() => _lookupLabel = null);
      }
      if (gen == _scanGeneration && mounted) {
        await _resumeScan(generation: gen);
      }
    }
  }

  void _onDetect(BarcodeCapture cap) {
    if (_busy) return;
    if (!mounted) return;

    // On iOS, cap.barcodes can be empty even when detection fires — filter early
    final barcodes = cap.barcodes
        .where((b) => b.rawValue != null && b.rawValue!.trim().isNotEmpty)
        .toList();

    if (barcodes.isEmpty) return;

    // Prefer QR codes over linear barcodes (QR is more reliable on iOS)
    final preferred = barcodes.firstWhere(
      (b) => b.format == BarcodeFormat.qrCode,
      orElse: () => barcodes.first,
    );

    final v = preferred.rawValue?.trim();
    if (v == null || v.isEmpty) return;
    if (!_debouncePass(v)) return;
    _flashScanConfirmed();
    _hadDetectThisVisit = true;
    _safariNoDetectTimer?.cancel();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (kIsWeb) {
      if (state == AppLifecycleState.paused) {
        if (cam != null) unawaited(cam.stop());
        unawaited(_stopWebLiveScanner());
        _scanLineCtrl.stop();
      } else if (state == AppLifecycleState.resumed) {
        unawaited(_initCamera());
        if (!_busy) _scanLineCtrl.repeat(reverse: true);
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (cam != null) unawaited(cam.stop());
      unawaited(_stopWebLiveScanner());
      _scanLineCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (_useWebDetectorPreview) {
        unawaited(_initCamera());
      } else if (cam != null) {
        unawaited(cam.start());
      }
      if (!_busy) {
        _scanLineCtrl.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (BarcodeCameraSession.mobile == _camera) {
      BarcodeCameraSession.mobile = null;
    }
    _safariNoDetectTimer?.cancel();
    _manualSearchDebounce?.cancel();
    _scanLineCtrl.dispose();
    _manualCtrl.removeListener(_onManualChanged);
    _manualCtrl.dispose();
    _manualFocus.removeListener(_onManualFocusChange);
    _manualFocus.dispose();
    if (kIsWeb) {
      _webLiveScanner = null;
      _camera = null;
    } else {
      unawaited(_stopWebLiveScanner());
      unawaited(_camera?.stop());
      _camera = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final desktopSplit = size.width >= 900;
    final cameraH = desktopSplit
        ? double.infinity
        : (size.height * (landscape ? 0.40 : 0.48))
            .clamp(landscape ? 180.0 : 260.0, landscape ? 280.0 : 420.0)
            .toDouble();
    final pendingSync = ref.watch(stockOfflinePendingCountProvider);
    final manualMatches = _manualMatches;
    final safariUpload = kIsWeb && preferUploadBarcodeOnWeb;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _goBack(context),
        ),
        title: const Text('Scan barcode'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'history':
                  context.push('/barcode/scan-history');
                case 'manual':
                  _manualFocus.requestFocus();
                case 'torch':
                  unawaited(_toggleTorch());
                case 'audit':
                  if (!_busy) unawaited(_startAuditSession());
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'history',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.history_rounded, size: 20),
                  title: Text('Scan history'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.keyboard_rounded, size: 20),
                  title: Text('Manual entry'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!kIsWeb)
                const PopupMenuItem(
                  value: 'torch',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.flashlight_on_rounded, size: 20),
                    title: Text('Torch'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'audit',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.fact_check_outlined, size: 20),
                  title: Text('Start audit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: desktopSplit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 46,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _scanTopSections(
                        context,
                        theme: theme,
                        size: size,
                        cameraH: 320,
                        safariUpload: safariUpload,
                        pendingSync: pendingSync,
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 54,
                  child: _scanManualSection(
                    context,
                    theme: theme,
                    manualMatches: manualMatches,
                  ),
                ),
              ],
            )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._scanTopSections(
            context,
            theme: theme,
            size: size,
            cameraH: cameraH,
            safariUpload: safariUpload,
            pendingSync: pendingSync,
          ),
          _scanManualSection(
            context,
            theme: theme,
            manualMatches: manualMatches,
            expanded: true,
          ),
        ],
      ),
    );
  }

  List<Widget> _scanTopSections(
    BuildContext context, {
    required ThemeData theme,
    required Size size,
    required double cameraH,
    required bool safariUpload,
    required int pendingSync,
  }) {
    return [
          if (safariUpload)
            MaterialBanner(
              content: const Text(
                'Live camera scan needs iOS 17 or newer in Safari. '
                'Upload a barcode photo or use manual search below.',
              ),
              actions: [
                TextButton(
                  onPressed: _busy ? null : _scanFromImage,
                  child: const Text('Upload photo'),
                ),
              ],
            ),
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
          if (_webCameraAwaitingGesture)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.touch_app_outlined,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to start camera',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Browsers require a tap before opening the camera.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => unawaited(_startCameraFromUserGesture()),
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Start camera'),
                  ),
                ],
              ),
            )
          else if (_cameraDenied)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.videocam_off_outlined,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    'Camera access needed',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cameraDeniedMessage ??
                        'Allow camera access to scan barcodes.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (kIsWeb) ...[
                    Text(
                      'Safari (installed app)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Open iPhone Settings\n'
                      '2. Scroll to Safari → Advanced → Website Data (or find this app on Home Screen)\n'
                      '3. Open Website Settings for Harisree\n'
                      '4. Set Camera to Allow\n'
                      '5. Return here and tap Try again',
                    ),
                    const SizedBox(height: 12),
                  ] else if (_cameraPermanent) ...[
                    Text(
                      'iPhone / Android',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Open device Settings\n'
                      '2. Find Harisree / Purchase Assistant\n'
                      '3. Enable Camera\n'
                      '4. Return and tap Try again',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open Settings'),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _cameraDenied = false;
                          _cameraPermanent = false;
                          _cameraDeniedMessage = null;
                        });
                        unawaited(_retryCameraAfterDenial());
                      },
                      child: const Text('Allow camera'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              _cameraDenied = false;
                              _cameraPermanent = false;
                              _cameraDeniedMessage = null;
                            });
                            unawaited(_retryCameraAfterDenial());
                          },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Without camera',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FallbackAction(
                    icon: Icons.photo_outlined,
                    label: 'Upload barcode photo',
                    onPressed: _busy ? null : _scanFromImage,
                  ),
                  _FallbackAction(
                    icon: Icons.keyboard,
                    label: 'Search by name or code',
                    onPressed: () => _manualFocus.requestFocus(),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _useWebDetectorPreview && _webLiveScanner != null
                          ? _webLiveScanner!.buildPreview()
                          : _camera != null
                              ? MobileScanner(
                                  controller: _camera!,
                                  onDetect: _onDetect,
                                )
                              : Container(
                              color: Colors.black87,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Starting camera…',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Center(
                      child: CustomPaint(
                        painter: ScannerReticlePainter(
                          color: HexaColors.brandPrimary,
                          confirmed: _scanConfirmed,
                        ),
                        child: Container(
                          width: math.min(320, size.width - 16),
                          height: 120,
                          alignment: Alignment.center,
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
                            final y = 140 * _scanLineCtrl.value;
                            return Align(
                              alignment: Alignment.center,
                              child: Transform.translate(
                                offset: Offset(0, y - 70),
                                child: Container(
                                  width: math.min(
                                    320,
                                    MediaQuery.sizeOf(context).width - 16,
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
                        color: Colors.black38,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            if (_lookupLabel != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Looking up $_lookupLabel',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_safariUploadNudgeShown && !_hadDetectThisVisit)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.orange.shade50,
                          child: ListTile(
                            leading: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.orange,
                            ),
                            title: const Text(
                              'Camera scanning not supported on this browser',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Upload a photo of the barcode, or type the item name below',
                            ),
                            trailing: ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_scanFromImage()),
                              child: const Text('Upload'),
                            ),
                          ),
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
    ];
  }

  Widget _scanManualSection(
    BuildContext context, {
    required ThemeData theme,
    required List<Map<String, dynamic>> manualMatches,
    bool expanded = false,
  }) {
    final child = Padding(
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
            expanded
                ? Expanded(
                    child: ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: manualMatches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) =>
                          _manualMatchTile(context, theme, manualMatches[i]),
                    ),
                  )
                : SizedBox(
                    height: 280,
                    child: ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: manualMatches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) =>
                          _manualMatchTile(context, theme, manualMatches[i]),
                    ),
                  ),
          ],
        ],
      ),
    );
    return expanded ? Expanded(child: child) : child;
  }

  Widget _manualMatchTile(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> item,
  ) {
    final id = item['id']?.toString();
    final name = item['name']?.toString() ?? 'Item';
    final code = item['item_code']?.toString();
    final barcode = item['barcode']?.toString();
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (code != null && code.isNotEmpty) code,
          if (barcode != null && barcode.isNotEmpty) 'Barcode $barcode',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: id == null || id.isEmpty
          ? null
          : () => context.push('/catalog/item/$id?source=scan'),
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

class ScannerReticlePainter extends CustomPainter {
  ScannerReticlePainter({required this.color, this.confirmed = false});
  final Color color;
  final bool confirmed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = confirmed ? const Color(0xFF16A34A) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = confirmed ? 4.0 : 3.0;

    final length = 16.0;
    final radius = 8.0;

    // Top-left
    final pathTL = Path()
      ..moveTo(0, length)
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..lineTo(length, 0);
    canvas.drawPath(pathTL, paint);

    // Top-right
    final pathTR = Path()
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(Offset(size.width, radius), radius: Radius.circular(radius))
      ..lineTo(size.width, length);
    canvas.drawPath(pathTR, paint);

    // Bottom-left
    final pathBL = Path()
      ..moveTo(0, size.height - length)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(Offset(radius, size.height), radius: Radius.circular(radius))
      ..lineTo(length, size.height);
    canvas.drawPath(pathBL, paint);

    // Bottom-right
    final pathBR = Path()
      ..moveTo(size.width - length, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(Offset(size.width, size.height - radius), radius: Radius.circular(radius))
      ..lineTo(size.width, size.height - length);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant ScannerReticlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.confirmed != confirmed;
}
