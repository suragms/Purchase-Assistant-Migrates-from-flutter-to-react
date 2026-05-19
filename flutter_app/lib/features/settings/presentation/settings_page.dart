import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, Uint8List, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/config/app_config.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart' show sessionCanManageUsers;
import '../../../core/models/session.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/maintenance/maintenance_payment_constants.dart';
import '../../../core/providers/cloud_expense_provider.dart';
import '../../../core/providers/cloud_payment_local_provider.dart';
import '../../../core/providers/maintenance_payment_provider.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/providers/analytics_kpi_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../reports/reports_prefs.dart';
import '../../../shared/widgets/search_picker_sheet.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Map<String, dynamic>? _billing;
  String? _billingErr;
  late final TextEditingController _brandingTitleCtrl;
  Uint8List? _pendingLogoBytes;
  String _pendingLogoFilename = 'logo.jpg';
  bool _brandingSaving = false;

  Razorpay? _razorpay;
  String _billingPlanCode = 'basic';
  bool _billingWa = false;
  bool _billingAi = false;
  Map<String, dynamic>? _billingQuote;
  bool _billingQuoteLoading = false;
  bool _checkoutBusy = false;

  bool _waSchedEnabled = false;
  String _waSchedType = 'weekly';
  TimeOfDay _waSchedTime = const TimeOfDay(hour: 8, minute: 0);
  late final TextEditingController _waPhoneCtrl;
  bool _waSchedBusy = false;
  bool _waSendingTest = false;

  int _superAdminGestureCount = 0;
  DateTime? _superAdminGestureAnchor;

  @override
  void initState() {
    super.initState();
    _brandingTitleCtrl = TextEditingController();
    _waPhoneCtrl = TextEditingController();
    if (!kIsWeb) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (dynamic response) {
        if (response is PaymentSuccessResponse) {
          unawaited(_onRazorpaySuccess(response));
        }
      });
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic response) {
        if (!mounted) return;
        final msg = response is PaymentFailureResponse
            ? (response.message ?? 'Payment did not complete')
            : 'Payment did not complete';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBilling();
      final s = ref.read(sessionProvider);
      final pb = s?.primaryBusiness;
      if (pb != null && mounted) {
        setState(() {
          _brandingTitleCtrl.text = pb.brandingTitle ?? '';
        });
      }
      unawaited(_loadWhatsAppSchedulePrefs());
    });
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _brandingTitleCtrl.dispose();
    _waPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWhatsAppSchedulePrefs() async {
    final enabled = await ReportsPrefs.getScheduleEnabled();
    final type = await ReportsPrefs.getScheduleType();
    final timeStr = await ReportsPrefs.getScheduleTime();
    final phone = await ReportsPrefs.getSchedulePhone();
    final parts = timeStr.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    if (!mounted) return;
    setState(() {
      _waSchedEnabled = enabled;
      _waSchedType = (type == 'daily' || type == 'weekly' || type == 'monthly')
          ? type
          : 'weekly';
      _waSchedTime = TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
      _waPhoneCtrl.text = phone;
    });
  }

  Future<void> _pickWhatsAppScheduleTime() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      final picked = await showTimePicker(
        context: context,
        initialTime: _waSchedTime,
      );
      if (picked != null && mounted) setState(() => _waSchedTime = picked);
      return;
    }
    final initial =
        DateTime(2020, 1, 1, _waSchedTime.hour, _waSchedTime.minute);
    var current = initial;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalCtx) => Container(
        height: 280,
        padding: const EdgeInsets.only(bottom: 8),
        margin: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(modalCtx).bottom),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(modalCtx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => modalCtx.pop(),
                    child: const Text('Cancel'),
                  ),
                  CupertinoButton(
                    onPressed: () {
                      modalCtx.pop();
                      if (!mounted) return;
                      setState(() {
                        _waSchedTime = TimeOfDay(
                          hour: current.hour,
                          minute: current.minute,
                        );
                      });
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initial,
                  use24hFormat: false,
                  onDateTimeChanged: (d) => current = d,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyWhatsAppSchedule() async {
    if (_waSchedBusy) return;
    setState(() => _waSchedBusy = true);
    try {
      await ReportsPrefs.setScheduleEnabled(_waSchedEnabled);
      await ReportsPrefs.setScheduleType(_waSchedType);
      await ReportsPrefs.setScheduleTime(
        '${_waSchedTime.hour.toString().padLeft(2, '0')}:${_waSchedTime.minute.toString().padLeft(2, '0')}',
      );
      await ReportsPrefs.setSchedulePhone(_waPhoneCtrl.text);
      String? serverSideSaveHint;
      // Best-effort: also save server-side schedule when backend supports it.
      // If the endpoint isn't deployed yet, we keep local reminders.
      try {
        final session = ref.read(sessionProvider);
        final bid = session?.primaryBusiness.id;
        if (bid != null && bid.isNotEmpty) {
          await ref.read(hexaApiProvider).patchWhatsAppReportSchedule(
                businessId: bid,
                enabled: _waSchedEnabled,
                scheduleType: _waSchedType,
                hour: _waSchedTime.hour,
                minute: _waSchedTime.minute,
                timezone: 'Asia/Kolkata',
                toE164: _waPhoneCtrl.text,
              ).timeout(const Duration(seconds: 6));
        }
      } catch (e) {
        serverSideSaveHint = 'Saved locally; server schedule not updated';
        debugPrint('wa schedule server-side save failed: $e');
      }
      if (_waSchedEnabled) {
        final ok = await LocalNotificationsService.instance
            .notificationPermissionGrantedForScheduling();
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Allow notifications in system settings to enable auto-report reminders.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
      await LocalNotificationsService.instance.scheduleWhatsAppReport(
        enabled: _waSchedEnabled,
        type: _waSchedType,
        hour: _waSchedTime.hour,
        minute: _waSchedTime.minute,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverSideSaveHint ??
                (_waSchedEnabled
                    ? 'WhatsApp report schedule saved'
                    : 'WhatsApp auto-report disabled'),
          ),
          backgroundColor: const Color(0xFF1B6B5A),
        ),
      );
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _waSchedBusy = false);
    }
  }

  Future<void> _sendTestWhatsAppReportNow() async {
    if (_waSendingTest) return;
    final phone = _waPhoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }
    setState(() => _waSendingTest = true);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, to) = switch (_waSchedType) {
        'daily' => (today, today),
        'monthly' => (today.subtract(const Duration(days: 29)), today),
        _ => (today.subtract(const Duration(days: 6)), today),
      };
      ref.read(analyticsDateRangeProvider.notifier).state = (from: from, to: to);
      final payload =
          await fetchReportsPurchasesLiveForAnalytics(ref as Ref);
      ref.invalidate(reportsPurchasesPayloadProvider);
      final purchases = payload.items;
      final agg = buildTradeReportAgg(purchases);

      final df = DateFormat('d MMM');
      final t = agg.totals;
      final parts = <String>[
        'Purchase Report (${df.format(from)} → ${df.format(to)})',
        '',
        'Total: ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(t.inr)}',
        _qtyLine(t),
      ]..removeWhere((e) => e.trim().isEmpty);
      final msg = Uri.encodeComponent(parts.join('\n'));
      final uri = Uri.parse('https://wa.me/$phone?text=$msg');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not installed or number invalid')),
        );
      }
    } catch (e, st) {
      logSilencedApiError(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _waSendingTest = false);
    }
  }

  String _qtyLine(TradeReportTotals t) {
    final p = <String>[];
    if (t.kg > 1e-9) p.add('${_n0(t.kg)} KG');
    if (t.bags > 1e-9) p.add('${_n0(t.bags)} BAGS');
    if (t.boxes > 1e-9) p.add('${_n0(t.boxes)} BOX');
    if (t.tins > 1e-9) p.add('${_n0(t.tins)} TIN');
    return p.join(' • ');
  }

  String _n0(double v) =>
      (v - v.roundToDouble()).abs() < 1e-6 ? '${v.round()}' : v.toStringAsFixed(1);

  Future<void> _fetchBillingQuote() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _billingQuoteLoading = true);
    try {
      final q = await ref.read(hexaApiProvider).billingQuote(
            businessId: session.primaryBusiness.id,
            planCode: _billingPlanCode,
            whatsappAddon: _billingWa,
            aiAddon: _billingAi,
          );
      if (mounted) {
        setState(() {
          _billingQuote = q;
          _billingQuoteLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _billingQuote = null;
          _billingQuoteLoading = false;
        });
      }
    }
  }

  Future<void> _onRazorpaySuccess(PaymentSuccessResponse r) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final pid = r.paymentId;
    final oid = r.orderId;
    final sig = r.signature;
    if (pid == null || oid == null || sig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Missing payment details — try again or contact support.')),
        );
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).billingVerify(
            businessId: session.primaryBusiness.id,
            razorpayOrderId: oid,
            razorpayPaymentId: pid,
            razorpaySignature: sig,
          );
      await _refreshBilling();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Payment confirmed. Your plan is updated.')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _payWithRazorpay() async {
    if (kIsWeb || _razorpay == null) return;
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;
    setState(() => _checkoutBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final order = await ref.read(hexaApiProvider).billingCreateOrder(
            businessId: session.primaryBusiness.id,
            planCode: _billingPlanCode,
            whatsappAddon: _billingWa,
            aiAddon: _billingAi,
          );
      final key = order['key_id']?.toString();
      final oid = order['order_id']?.toString();
      final rawAmt = order['amount_paise'];
      final amount =
          rawAmt is int ? rawAmt : int.tryParse(rawAmt?.toString() ?? '') ?? 0;
      if (key == null || oid == null || amount <= 0) {
        throw StateError('Invalid order from server');
      }
      _razorpay!.open({
        'key': key,
        'amount': amount,
        'currency': order['currency']?.toString() ?? 'INR',
        'name': AppConfig.appName,
        'description': 'Workspace subscription',
        'order_id': oid,
        'prefill': <String, String>{},
      });
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  Future<void> _pickLogo() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingLogoBytes = bytes;
      _pendingLogoFilename =
          x.name.trim().isNotEmpty ? x.name.trim() : 'logo.jpg';
    });
  }

  Future<void> _saveBranding() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    if (session.primaryBusiness.role != 'owner') return;
    setState(() => _brandingSaving = true);
    final api = ref.read(hexaApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_pendingLogoBytes != null) {
        await api.uploadBusinessLogoBytes(
          businessId: bid,
          bytes: _pendingLogoBytes!,
          filename: _pendingLogoFilename,
        );
      }
      await api.patchBusinessBranding(
        businessId: bid,
        brandingTitle: _brandingTitleCtrl.text.trim(),
      );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (!mounted) return;
      final pb = ref.read(sessionProvider)?.primaryBusiness;
      if (pb != null) {
        _brandingTitleCtrl.text = pb.brandingTitle ?? '';
      }
      setState(() => _pendingLogoBytes = null);
      messenger.showSnackBar(const SnackBar(content: Text('Branding saved')));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  Future<void> _clearLogo() async {
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;
    setState(() => _brandingSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            brandingLogoUrl: '',
          );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (mounted) {
        setState(() => _pendingLogoBytes = null);
        messenger.showSnackBar(const SnackBar(content: Text('Logo removed')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  Future<void> _refreshBilling() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    try {
      final m = await api.billingStatus(businessId: bid);
      if (mounted) {
        final sub = m['subscription'] as Map<String, dynamic>?;
        setState(() {
          _billing = m;
          _billingErr = null;
          if (sub != null) {
            var pc = sub['plan_code']?.toString().toLowerCase() ?? 'basic';
            if (!const {'basic', 'pro', 'premium'}.contains(pc)) pc = 'basic';
            _billingPlanCode = pc;
            _billingWa = sub['whatsapp_addon'] == true;
            _billingAi = sub['ai_addon'] == true;
          }
        });
        await _fetchBillingQuote();
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _billingErr = e.message ?? 'Billing unavailable';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    ref.listen<Session?>(sessionProvider, (previous, next) {
      final pb = next?.primaryBusiness;
      if (pb == null) return;
      if (previous?.primaryBusiness.id != pb.id) {
        _brandingTitleCtrl.text = pb.brandingTitle ?? '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _pendingLogoBytes = null);
        });
      }
    });
    final isOwner = session?.primaryBusiness.role == 'owner';
    final canManageUsers =
        session != null && sessionCanManageUsers(session);
    final showBillingSection =
        isOwner && (ModalRoute.of(context)?.settings.name == '/settings/billing');
    final pb = session?.primaryBusiness;
    final onSurf = cs.onSurface;
    final notifOptIn = ref.watch(localNotificationsOptInProvider);

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: onSurf)),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: onSurf),
          onPressed: () => context.popOrGo('/home'),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Account',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: ListTile(
              leading: Icon(Icons.person_outline_rounded, color: cs.primary),
              title: const Text('Session'),
              subtitle: Text(session != null
                  ? 'Signed in · ${session.primaryBusiness.name}'
                  : 'Not signed in'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Quick actions',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.document_scanner_outlined,
                      color: cs.primary),
                  title: const Text('Scan purchase bill'),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: cs.outline),
                  onTap: () => context.pushNamed('purchase_scan'),
                ),
                ListTile(
                  leading:
                      Icon(Icons.add_shopping_cart_outlined, color: cs.primary),
                  title: const Text('New purchase'),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: cs.outline),
                  onTap: () => context.go('/purchase/new'),
                ),
                ListTile(
                  leading: Icon(Icons.edit_note_rounded, color: cs.primary),
                  title: const Text('Resume purchase draft'),
                  subtitle: const Text('Opens purchase entry if a draft exists'),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: cs.outline),
                  onTap: () =>
                      context.go('/purchase/new?resumeDraft=true'),
                ),
                ListTile(
                  leading: Icon(Icons.mic_none_rounded, color: cs.primary),
                  title: const Text('Voice note'),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: cs.outline),
                  onTap: () => context.push('/voice'),
                ),
                ListTile(
                  leading: Icon(Icons.history_rounded, color: cs.primary),
                  title: const Text('Purchase history'),
                  trailing:
                      Icon(Icons.chevron_right_rounded, color: cs.outline),
                  onTap: () => context.go('/purchase'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Purchases & sharing',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Local notifications'),
                    subtitle: const Text('Reminders and follow-ups on this device'),
                    value: notifOptIn,
                    onChanged: (v) => unawaited(
                      ref.read(localNotificationsOptInProvider.notifier).setValue(v),
                    ),
                  ),
                  const Divider(height: 16),
                  Text(
                    'WhatsApp Reports',
                    style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Schedules a reminder on this device. Tapping the notification builds the report and opens WhatsApp — nothing is sent automatically without your action.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-report'),
                    subtitle: const Text('Local reminder at the time you choose'),
                    value: _waSchedEnabled,
                    onChanged: (v) => setState(() => _waSchedEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _waSchedType,
                    decoration: const InputDecoration(
                      labelText: 'Schedule',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (v) => setState(() => _waSchedType = v ?? 'weekly'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_pickWhatsAppScheduleTime()),
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('Time: ${_waSchedTime.format(context)}'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _waPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Send to (phone)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _waSchedBusy ? null : () => unawaited(_applyWhatsAppSchedule()),
                    child: _waSchedBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save WhatsApp schedule'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _waSendingTest
                        ? null
                        : () => unawaited(_sendTestWhatsAppReportNow()),
                    child: _waSendingTest
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send test report now'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Business',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pb?.name ?? '—',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (session != null)
                    Text(
                      'Role: ${pb!.role} · Shown in app: ${pb.effectiveDisplayTitle}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  if (isOwner && pb != null) ...[
                    const SizedBox(height: 16),
                    Text('Workspace branding',
                        style: tt.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _brandingTitleCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'In-app title',
                        hintText: 'Leave empty to use business name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LogoPreview(
                          pendingBytes: _pendingLogoBytes,
                          networkUrl: pb.brandingLogoUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _brandingSaving ? null : _pickLogo,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Choose logo'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed:
                                    _brandingSaving ? null : _saveBranding,
                                child: _brandingSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Save branding'),
                              ),
                              TextButton(
                                onPressed: _brandingSaving ||
                                        (_pendingLogoBytes == null &&
                                            (pb.brandingLogoUrl
                                                    ?.trim()
                                                    .isEmpty ??
                                                true))
                                    ? null
                                    : () {
                                        if (_pendingLogoBytes != null) {
                                          setState(
                                              () => _pendingLogoBytes = null);
                                        } else {
                                          _clearLogo();
                                        }
                                      },
                                child: Text(_pendingLogoBytes != null
                                    ? 'Discard image'
                                    : 'Remove logo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else if (session != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Only owners can change the in-app title and logo.',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_outlined, color: cs.primary),
                    title: const Text('Purchase order / business profile'),
                    subtitle: const Text(
                      'GSTIN, address, phone for PDF purchase orders',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/settings/business'),
                  ),
                  if (canManageUsers) ...[
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.group_outlined, color: cs.primary),
                      title: const Text('Users & roles'),
                      subtitle: const Text(
                        'Staff and manager logins for this workspace',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/settings/users'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Operations',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.playlist_add_check_rounded, color: cs.primary),
                  title: const Text('Reorder list'),
                  subtitle: const Text('Items flagged for reorder'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/stock/reorder'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.print_outlined, color: cs.primary),
                  title: const Text('Print barcodes (bulk)'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/barcode/bulk-print'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
                  title: const Text('Scan item'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/barcode/scan'),
                ),
              ],
            ),
          ),
          if (session?.isSuperAdmin == true) ...[
            const SizedBox(height: 20),
            Text('Admin',
                style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Card(
              color: context.adaptiveCard,
              child: ListTile(
                leading: Icon(Icons.admin_panel_settings_outlined, color: cs.primary),
                title: const Text('Super admin'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/admin'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Data',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.groups_outlined, color: cs.primary),
                  title: const Text('Suppliers & brokers'),
                  subtitle:
                      const Text('Contacts hub — categories, items, people.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/contacts'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.inventory_2_outlined, color: cs.primary),
                  title: const Text('Item catalog'),
                  subtitle: const Text(
                      'Categories and items for faster entry lines.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/catalog'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.folder_zip_outlined, color: cs.primary),
                  title: const Text('Backup'),
                  subtitle: const Text(
                      'Download purchases CSV (ZIP) for your records.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/backup'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.straighten_rounded, color: cs.primary),
                  title: const Text('Units'),
                  subtitle:
                      const Text('Bag, kg, piece — enforced on entry lines.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Cloud hosting',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (session != null) _CloudSettingsCard(businessId: session.primaryBusiness.id),
          const SizedBox(height: 20),
          Text('Maintenance payment',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const _MaintenanceSettingsCard(),
          const SizedBox(height: 20),
          Text('Troubleshooting',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: ListTile(
              leading: Icon(Icons.sync_rounded, color: cs.primary),
              title: const Text('Refresh all stats'),
              subtitle: const Text(
                'Reloads home, reports, contacts KPIs, and your purchase log from the server. Use when totals look wrong after deletes or edits.',
              ),
              onTap: () {
                invalidateBusinessAggregates(ref);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Refreshing numbers…')),
                );
              },
            ),
          ),
          if (showBillingSection) ...[
            const SizedBox(height: 20),
            Text('Subscription',
                style: tt.titleSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Card(
              color: context.adaptiveCard,
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Plan & add-ons',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                          onPressed: _refreshBilling,
                          child: const Text('Refresh')),
                    ],
                  ),
                  if (_billingErr != null)
                    Text(_billingErr!,
                        style: tt.bodySmall?.copyWith(color: Colors.redAccent))
                  else if (_billing == null)
                    Text('Loading…',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant))
                  else ...[
                    Text(
                      _billing!['subscription'] == null
                          ? 'No subscription row yet — defaults apply until you pay.'
                          : 'Status: ${_billing!['subscription']['status']} · Bundle: ${_billing!['subscription']['whatsapp_addon']} · AI: ${_billing!['subscription']['ai_addon']}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payments: ${(_billing!['razorpay_configured'] == true) ? 'ready' : 'not configured'} · plan enforcement: ${_billing!['billing_enforce']}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checkout is completed securely; your payment is confirmed before your plan updates.',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (isOwner) ...[
                      const SizedBox(height: 16),
                      if (_billing!['razorpay_configured'] != true)
                        Text(
                          'In-app payment needs Razorpay keys on the server (environment or admin platform integration).',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, height: 1.35),
                        )
                      else if (kIsWeb)
                        Text(
                          'Razorpay checkout runs in the Android or iOS app — not in this web build.',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, height: 1.35),
                        )
                      else ...[
                        Text('Renew or change plan',
                            style: tt.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Plan',
                            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        OutlinedButton(
                          onPressed: () async {
                            final v = await showSearchPickerSheet<String>(
                              context: context,
                              title: 'Choose plan',
                              rows: const [
                                SearchPickerRow(value: 'basic', title: 'Basic'),
                                SearchPickerRow(value: 'pro', title: 'Pro'),
                                SearchPickerRow(value: 'premium', title: 'Premium'),
                              ],
                              selectedValue: _billingPlanCode,
                              initialChildFraction: 0.42,
                            );
                            if (!mounted || v == null) return;
                            setState(() => _billingPlanCode = v);
                            unawaited(_fetchBillingQuote());
                          },
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              switch (_billingPlanCode) {
                                'pro' => 'Pro',
                                'premium' => 'Premium',
                                _ => 'Basic',
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Bundle add-on (legacy)'),
                          subtitle: const Text(
                              'Optional extra bundle line item; often paired with AI add-on in quotes.'),
                          value: _billingWa,
                          onChanged: (v) {
                            setState(() => _billingWa = v);
                            unawaited(_fetchBillingQuote());
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('AI add-on'),
                          value: _billingAi,
                          onChanged: (v) {
                            setState(() => _billingAi = v);
                            unawaited(_fetchBillingQuote());
                          },
                        ),
                        if (_billingQuoteLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(),
                          )
                        else if (_billingQuote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format((_billingQuote!['amount_inr'] as num?) ?? 0)} / month',
                              style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: onSurf),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: (_checkoutBusy ||
                                  _billingQuoteLoading ||
                                  _billingQuote == null)
                              ? null
                              : () => unawaited(_payWithRazorpay()),
                          icon: const Icon(Icons.payment_rounded),
                          label: Text(_checkoutBusy
                              ? 'Opening checkout…'
                              : 'Pay with Razorpay'),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
          ],
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onLongPress: () {
                if (session?.isSuperAdmin != true) return;
                final now = DateTime.now();
                final anchor = _superAdminGestureAnchor;
                if (anchor == null ||
                    now.difference(anchor) > const Duration(seconds: 4)) {
                  _superAdminGestureCount = 0;
                }
                _superAdminGestureAnchor = now;
                setState(() => _superAdminGestureCount++);
                if (_superAdminGestureCount >= 3) {
                  _superAdminGestureCount = 0;
                  _superAdminGestureAnchor = null;
                  context.push('/admin');
                }
              },
              child: Text(
                'Version ${AppConfig.packageVersion}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceSettingsCard extends ConsumerWidget {
  const _MaintenanceSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(maintenancePaymentControllerProvider);
    final cs = Theme.of(context).colorScheme;
    return async.when(
      skipLoadingOnReload: true,
      data: (v) {
        if (v?.userVisibleError != null) {
          return Card(
            color: context.adaptiveCard,
            child: ListTile(
              title: Text(
                v!.userVisibleError!,
                style: const TextStyle(color: HexaColors.textSecondary),
              ),
              trailing: TextButton(
                onPressed: () => ref
                    .read(maintenancePaymentControllerProvider.notifier)
                    .load(),
                child: const Text('Retry'),
              ),
            ),
          );
        }
        if (v?.current?.isPaid == true) {
          return Card(
            color: context.adaptiveCard,
            child: ListTile(
              leading: Icon(Icons.check_circle_rounded, color: cs.tertiary),
              title: const Text('Maintenance'),
              subtitle: const Text('Paid for this month'),
              trailing: TextButton(
                onPressed: () => context.push('/settings/maintenance/history'),
                child: const Text('History'),
              ),
            ),
          );
        }
        return Card(
          color: context.adaptiveCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(Icons.account_balance_outlined, color: cs.primary),
                title: const Text('UPI ID (fixed)'),
                subtitle: const SelectableText(
                  MaintenancePaymentConstants.upiId,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.payments_outlined, color: cs.primary),
                title: const Text('Amount'),
                subtitle: Text(
                  '₹${MaintenancePaymentConstants.amountInr} / month — not editable in the app',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined,
                    color: cs.primary),
                value: v?.remindersEnabled ?? true,
                onChanged: (b) {
                  unawaited(ref
                      .read(maintenancePaymentControllerProvider.notifier)
                      .setRemindersEnabled(b));
                },
                title: const Text('Local reminders'),
                subtitle: const Text(
                  'Up to three reminders, 24 hours apart, for this month when unpaid',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.history_rounded, color: cs.primary),
                title: const Text('View payment history'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/settings/maintenance/history'),
              ),
            ],
          ),
        );
      },
      loading: () => const Card(
        child: ListTile(
          title: Text('Loading…'),
        ),
      ),
      error: (_, __) => Card(
        child: ListTile(
          title: const Text('Could not load maintenance'),
          trailing: TextButton(
            onPressed: () => ref
                .read(maintenancePaymentControllerProvider.notifier)
                .load(),
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }
}

class _CloudSettingsCard extends ConsumerWidget {
  const _CloudSettingsCard({required this.businessId});

  final String businessId;

  static ButtonStyle get _btnCompact => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> m,
  ) async {
    final amtCtrl = TextEditingController(
      text: ((m['amount_inr'] as num?) ?? 0).toString(),
    );
    final dueCtrl = TextEditingController(
      text: (m['due_day'] ?? 1).toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud cost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (Rs. / month)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Due day of month (1–31)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      amtCtrl.dispose();
      dueCtrl.dispose();
      return;
    }
    final amt = double.tryParse(amtCtrl.text.trim());
    final due = int.tryParse(dueCtrl.text.trim());
    amtCtrl.dispose();
    dueCtrl.dispose();
    if (amt == null || amt <= 0 || due == null || due < 1 || due > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid amount or due day')),
      );
      return;
    }
    try {
      await ref.read(hexaApiProvider).patchCloudCost(
            businessId: businessId,
            amountInr: amt,
            dueDay: due,
          );
      ref.invalidate(cloudCostProvider);
      invalidateBusinessAggregates(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save. Please try again.'),
          ),
        );
      }
    }
  }

  String _cloudUpiUri({required double amountInr}) {
    if (AppConfig.cloudUpiVpa.isEmpty) return '';
    return 'upi://pay?pa=${Uri.encodeComponent(AppConfig.cloudUpiVpa)}'
        '&pn=${Uri.encodeComponent(AppConfig.cloudUpiPayeeName)}'
        '&am=${amountInr.toStringAsFixed(0)}'
        '&cu=INR';
  }

  Future<void> _openUpiExternal(
    BuildContext context, {
    required double amountInr,
  }) async {
    if (AppConfig.cloudUpiVpa.isEmpty) return;
    final s = _cloudUpiUri(amountInr: amountInr);
    if (s.isEmpty) return;
    final uri = Uri.parse(s);
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No UPI app found')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No UPI app found')),
        );
      }
    }
  }

  void _showQr(
    BuildContext context, {
    required double amountInr,
  }) {
    if (AppConfig.cloudUpiVpa.isEmpty) return;
    final data = _cloudUpiUri(amountInr: amountInr);
    if (data.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan to pay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: data,
              size: 220,
            ),
            const SizedBox(height: 12),
            Text(
              'UPI ID: ${AppConfig.cloudUpiVpa}',
              style: Theme.of(ctx).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Scan to pay with any UPI app',
              style: Theme.of(ctx)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmMarkPaid(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm payment completed?'),
        content: const Text('Only confirm after you have completed the UPI transfer.'),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => ctx.pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(cloudPaymentLocalProvider.notifier).markCurrentMonthPaid();
      ref.invalidate(cloudCostProvider);
      invalidateBusinessAggregates(ref);
    }
  }

  /// When the server row cannot be loaded, show the same card layout using
  /// local [cloudPaymentLocalProvider] only — no error banner (BUG-R5).
  static Map<String, dynamic> _offlineCloudCostPlaceholder() => {
        'name': 'Cloud hosting',
        'amount_inr': 0,
        'next_due_date': '—',
        'show_alert': false,
        'in_pre_due_window': false,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(cloudPaymentLocalProvider);
    final async = ref.watch(cloudCostProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => _buildCloudCard(
        context,
        ref,
        m: _offlineCloudCostPlaceholder(),
        local: local,
        serverUnavailable: true,
        loading: true,
      ),
      error: (_, __) => _buildCloudCard(
        context,
        ref,
        m: _offlineCloudCostPlaceholder(),
        local: local,
        serverUnavailable: true,
        loading: false,
      ),
      data: (m) {
        if (m.isEmpty) return const SizedBox.shrink();
        return _buildCloudCard(
          context,
          ref,
          m: m,
          local: local,
          serverUnavailable: false,
          loading: false,
        );
      },
    );
  }

  Widget _buildCloudCard(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic> m,
    required CloudPaymentLocalView local,
    required bool serverUnavailable,
    required bool loading,
  }) {
    final cs = Theme.of(context).colorScheme;
    final amt = (m['amount_inr'] as num?)?.toDouble() ?? 0;
    final next = m['next_due_date']?.toString() ?? '—';
    final need = m['show_alert'] == true;
    final inPre = m['in_pre_due_window'] == true;
    final paidLocal = local.isPaid;
    final iconColor = paidLocal
        ? const Color(0xFF16A34A)
        : (need
            ? Colors.redAccent
            : (inPre ? Colors.orange : cs.primary));

    return Card(
          color: context.adaptiveCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m['name']?.toString() ?? 'Cloud',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      (serverUnavailable && amt <= 0) ? '—' : '₹${amt.round()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (loading) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Loading billing details…',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ] else if (serverUnavailable) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Payment status is kept on this device. Monthly amount syncs when the server is available.',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (paidLocal && local.paidAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Paid ✔',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.green[800],
                    ),
                  ),
                  Text(
                    'Paid on ${DateFormat.yMMMd().format(local.paidAt!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    need
                        ? 'Overdue · $next'
                        : (inPre ? 'Due soon · $next' : 'Next: $next'),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!paidLocal) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!serverUnavailable)
                        OutlinedButton(
                          style: _btnCompact,
                          onPressed: () => _edit(context, ref, m),
                          child:
                              const Text('Edit', style: TextStyle(fontSize: 12)),
                        ),
                      if (AppConfig.cloudUpiVpa.isNotEmpty) ...[
                        if (!serverUnavailable && amt > 0)
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _openUpiExternal(
                              context,
                              amountInr: amt,
                            ),
                            child: const Text('Pay via UPI',
                                style: TextStyle(fontSize: 12)),
                          ),
                        OutlinedButton(
                        style: _btnCompact,
                          onPressed: () async {
                            await Clipboard.setData(
                              const ClipboardData(
                                text: AppConfig.cloudUpiVpa,
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('UPI ID copied'),
                              ),
                            );
                          },
                          child: const Text('Copy UPI ID',
                              style: TextStyle(fontSize: 12)),
                        ),
                        if (!serverUnavailable && amt > 0)
                          OutlinedButton(
                            style: _btnCompact,
                            onPressed: () => _showQr(
                              context,
                              amountInr: amt,
                            ),
                            child: const Text('Show QR',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                      FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => unawaited(
                          _confirmMarkPaid(context, ref),
                        ),
                        child: const Text('Mark as paid',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({this.pendingBytes, this.networkUrl});

  final Uint8List? pendingBytes;
  final String? networkUrl;

  @override
  Widget build(BuildContext context) {
    final w = 72.0;
    final h = 72.0;
    if (pendingBytes != null && pendingBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          pendingBytes!,
          width: w,
          height: h,
          fit: BoxFit.cover,
        ),
      );
    }
    final u = networkUrl?.trim();
    if (u != null && u.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          u,
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(w, h),
        ),
      );
    }
    return _placeholder(w, h);
  }

  Widget _placeholder(double w, double h) {
    return Builder(
      builder: (context) {
        final o = Theme.of(context).colorScheme.onSurfaceVariant;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: HexaColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: HexaColors.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.storefront_outlined,
              color: o.withValues(alpha: 0.6)),
        );
      },
    );
  }
}
