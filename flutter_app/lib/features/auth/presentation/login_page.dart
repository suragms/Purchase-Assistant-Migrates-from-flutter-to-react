import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/biometric_login.dart';
import '../../../core/auth/auth_failure_policy.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import 'auth_brand_assets.dart';
import 'widgets/auth_input_styles.dart';
import 'widgets/auth_network_error_banner.dart';
import 'widgets/auth_page_shell.dart';

/// Keyboard-safe, centered card login (no hero image) — iOS + web friendly.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _loading = false;
  bool _obscure = true;
  bool _showValidation = false;
  bool _showNetworkBanner = false;
  DioException? _lastNetworkError;
  String? _inlineAuthError;
  bool _handledDupEmailQuery = false;
  bool _handledOwnerOnlyNotice = false;
  bool _bioReady = false;
  String? _bioEmail;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _loginEmail.addListener(_clearInlineErrors);
    _loginPass.addListener(_clearInlineErrors);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animController.forward();
        _tryResumeSession();
      }
      unawaited(_loadBiometricState());
    });
  }

  Future<void> _loadBiometricState() async {
    final email = await BiometricLogin.savedEmail();
    final can = await BiometricLogin.isAvailable();
    final t = await ref.read(tokenStoreProvider).read();
    final hasTokens = t.access != null && t.refresh != null;
    if (!mounted) return;
    setState(() {
      _bioEmail = email;
      _bioReady = can && email != null && email.isNotEmpty && hasTokens;
    });
  }

  void _clearInlineErrors() {
    if (_inlineAuthError != null) {
      setState(() => _inlineAuthError = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_handledDupEmailQuery) {
      try {
        final q = GoRouterState.of(context).uri.queryParameters['msg'];
        if (q == 'exists') {
          _handledDupEmailQuery = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack('This email is already registered. Please sign in below.');
            if (!mounted) return;
            context.go('/login');
          });
        }
      } catch (_) {}
    }
    if (!_handledOwnerOnlyNotice) {
      try {
        final notice =
            GoRouterState.of(context).uri.queryParameters['notice'];
        if (notice == 'session_expired') {
          _handledOwnerOnlyNotice = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack('Session expired. Please sign in again.');
          });
        } else if (notice == 'owner_only') {
          _handledOwnerOnlyNotice = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack(
              'Accounts are created by your owner. Sign in with the credentials they shared.',
            );
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _loginEmail.removeListener(_clearInlineErrors);
    _loginPass.removeListener(_clearInlineErrors);
    _loginEmail.dispose();
    _loginPass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    final email = _loginEmail.text.trim();
    final p = _loginPass.text;
    return email.contains('@') && email.length >= 5 && p.length >= 6;
  }

  String? _emailError() {
    if (!_showValidation) return null;
    final s = _loginEmail.text.trim();
    if (s.isEmpty || !s.contains('@')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _passError() {
    if (!_showValidation) return null;
    if (_loginPass.text.isEmpty || _loginPass.text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _goPostAuth() {
    final s = ref.read(sessionProvider);
    if (s == null) return;
    context.go(authenticatedHomePath(s));
  }

  Future<void> _tryResumeSession() async {
    if (ref.read(authSessionExpiredProvider) ||
        ref.read(auth401CircuitOpenProvider)) {
      return;
    }
    final t = await ref.read(tokenStoreProvider).read();
    if (t.access == null || t.refresh == null) return;
    if (ref.read(sessionProvider) != null) {
      if (mounted) _goPostAuth();
      return;
    }
    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    try {
      await ref.read(sessionProvider.notifier).restore().timeout(
            kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 25),
          );
    } on DioException catch (e) {
      if (mounted && isDioNoConnectionError(e)) {
        setState(() {
          _lastNetworkError = e;
          _showNetworkBanner = true;
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (ref.read(sessionProvider) != null) {
      _goPostAuth();
    }
  }

  void _authSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _retryAfterNetwork() {
    setState(() {
      _showNetworkBanner = false;
      _lastNetworkError = null;
      _inlineAuthError = null;
    });
    if (_isFormValid) {
      _signIn();
    } else {
      setState(() => _showValidation = true);
    }
  }

  Future<void> _signIn() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _inlineAuthError = null;
    });
    if (!_isFormValid) return;

    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    try {
      final email = _loginEmail.text.trim();
      await ref.read(sessionProvider.notifier).login(
            email: email,
            password: _loginPass.text,
          );
      await BiometricLogin.saveEmail(email);
      if (mounted) _goPostAuth();
    } on DioException catch (e) {
      if (!mounted) return;
      if (isDioNoConnectionError(e)) {
        setState(() {
          _lastNetworkError = e;
          _showNetworkBanner = true;
        });
        return;
      }
      final sc = e.response?.statusCode;
      if (sc == 401) {
        setState(() {
          _inlineAuthError = 'Invalid email or password. Try again.';
        });
        return;
      }
      if (sc == 403) {
        final detail = e.response?.data;
        final msg = detail is Map ? detail['detail']?.toString() : null;
        setState(() {
          _inlineAuthError = msg?.toLowerCase().contains('blocked') == true
              ? 'This account is blocked. Contact your owner.'
              : (msg?.toLowerCase().contains('inactive') == true
                  ? 'This account is inactive.'
                  : 'Sign-in not allowed for this account.');
        });
        return;
      }
      if (sc == 422) {
        setState(() {
          _inlineAuthError =
              'Use your full login email (e.g. 1234567890@staff.harisree.local) and password from the owner.';
        });
        return;
      }
      setState(() {
        _inlineAuthError = friendlyAuthError(e, context: AuthErrorContext.login);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineAuthError = 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithBiometric() async {
    if (_loading || !_bioReady) return;
    final ok = await BiometricLogin.authenticate();
    if (!ok || !mounted) return;
    if (_bioEmail != null && _bioEmail!.isNotEmpty) {
      _loginEmail.text = _bioEmail!;
    }
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).restore();
      if (mounted && ref.read(sessionProvider) != null) {
        _goPostAuth();
      } else if (mounted) {
        setState(() {
          _inlineAuthError = 'Session expired — sign in with password once.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineAuthError = 'Biometric sign-in failed. Use password.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _err(String? m) {
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        m,
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build — responsive: mobile gets full-width frosted layout, desktop unchanged
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final eErr = _emailError();
    final pErr = _passError();

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5F2),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: context.isMobileLayout
            ? _buildMobileLayout(eErr, pErr)
            : _buildDesktopLayout(eErr, pErr),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Desktop / Tablet layout — preserved exactly as-is
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(String? eErr, String? pErr) {
    return AuthPageShell(
      children: [
        AuthFormCard(
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warehouse_outlined,
                      size: 36,
                      color: HexaColors.brandPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Harisree Agency',
                            style: HexaDsType.heading(24,
                                color: HexaDsColors.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Warehouse Management',
                            style: HexaDsType.body(14,
                                color: HexaDsColors.textMuted,
                                weight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign In',
                  textAlign: TextAlign.center,
                  style: HexaDsType.heading(20, color: HexaDsColors.textPrimary),
                ),
                const SizedBox(height: 12),
                if (_showNetworkBanner)
                  AuthNetworkErrorBanner(
                    onRetry: _retryAfterNetwork,
                    title: authUnreachableBannerTitle(_lastNetworkError),
                    detail: authServerUnreachableDetail(_lastNetworkError),
                  ),
                TextField(
                  controller: _loginEmail,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  onSubmitted: (_) => _passFocus.requestFocus(),
                  decoration: authFilledDecoration(
                    'Email',
                    icon: Icons.email_outlined,
                    err: eErr != null,
                  ),
                ),
                _err(eErr),
                TextField(
                  controller: _loginPass,
                  focusNode: _passFocus,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  onSubmitted: (_) {
                    if (_isFormValid) _signIn();
                  },
                  decoration: authFilledDecoration(
                    'Password',
                    icon: Icons.key_rounded,
                    err: pErr != null,
                    suffix: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF6B7280),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                _err(pErr),
                if (_inlineAuthError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _inlineAuthError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_bioReady) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.tonalIcon(
                      onPressed: _loading ? null : _signInWithBiometric,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            HexaColors.brandPrimary.withValues(alpha: 0.12),
                        foregroundColor: HexaColors.brandPrimary,
                      ),
                      icon: const Icon(Icons.fingerprint, size: 28),
                      label: const Text(
                        'Sign in with fingerprint / Face ID',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (_bioEmail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _bioEmail!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading
                        ? null
                        : (_isFormValid
                            ? _signIn
                            : () => setState(() => _showValidation = true)),
                    style: FilledButton.styleFrom(
                      backgroundColor: HexaColors.brandPrimary,
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                      disabledForegroundColor: const Color(0xFF6B7280),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            context.go('/forgot-password');
                          },
                    child: Text(
                      'Forgot password?',
                      style: HexaDsType.body(12,
                          color: HexaDsColors.textMuted,
                          weight: FontWeight.w500),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Contact your manager to reset password',
                    style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                  ),
                ),
                const SizedBox(height: 8),
                if (AppConfig.buildSha.isNotEmpty)
                  Text(
                    'Build ${AppConfig.buildSha}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                Text(
                  '© 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Mobile layout — premium full-width frosted-glass design
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildMobileLayout(String? eErr, String? pErr) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMobileBackground(),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 32, 20, 24 + bottom),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: _buildGlassContainer(eErr, pErr),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          AuthBrandAssets.background,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.atmosphereGradient),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF062E28).withValues(alpha: 0.55),
                  HexaColors.brandPrimary.withValues(alpha: 0.65),
                  HexaColors.brandBackground.withValues(alpha: 0.80),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassContainer(String? eErr, String? pErr) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLogoSection(),
                const SizedBox(height: 32),
                Text(
                  'Sign In',
                  textAlign: TextAlign.center,
                  style: HexaDsType.heading(28,
                      color: HexaDsColors.textPrimary),
                ),
                const SizedBox(height: 32),
                if (_showNetworkBanner)
                  AuthNetworkErrorBanner(
                    onRetry: _retryAfterNetwork,
                    title: authUnreachableBannerTitle(_lastNetworkError),
                    detail: authServerUnreachableDetail(_lastNetworkError),
                  ),
                _buildMobileTextField(
                  controller: _loginEmail,
                  focusNode: _emailFocus,
                  hint: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  error: eErr,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                _buildMobileTextField(
                  controller: _loginPass,
                  focusNode: _passFocus,
                  hint: 'Password',
                  icon: Icons.key_rounded,
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  error: pErr,
                  suffix: _buildPasswordToggle(),
                  onSubmitted: (_) {
                    if (_isFormValid) _signIn();
                  },
                ),
                if (_inlineAuthError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _inlineAuthError!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_bioReady) ...[
                  const SizedBox(height: 16),
                  _buildBiometricButton(),
                  if (_bioEmail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _bioEmail!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                _buildSignInButton(),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _loading
                        ? null
                        : () => context.go('/forgot-password'),
                    child: Text(
                      'Forgot password?',
                      style: HexaDsType.body(14,
                          color: HexaDsColors.textMuted,
                          weight: FontWeight.w500),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Contact your manager to reset password',
                    style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                  ),
                ),
                const SizedBox(height: 8),
                if (AppConfig.buildSha.isNotEmpty)
                  Text(
                    'Build ${AppConfig.buildSha}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                Text(
                  '© 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              AuthBrandAssets.logo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: HexaColors.brandPrimary,
                alignment: Alignment.center,
                child: const Text(
                  'H',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Harisree Agency',
          textAlign: TextAlign.center,
          style: HexaDsType.heading(26, color: HexaDsColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'Warehouse Management',
          textAlign: TextAlign.center,
          style: HexaDsType.body(15,
              color: HexaDsColors.textMuted, weight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildMobileTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<String>? autofillHints,
    String? error,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            obscureText: obscure,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              isDense: false,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: error != null
                      ? Colors.red.shade500
                      : const Color(0xFFE5E7EB),
                  width: error != null ? 1.5 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                    color: HexaColors.brandPrimary, width: 1.5),
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordToggle() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: child,
      ),
      child: IconButton(
        key: ValueKey(_obscure),
        tooltip: _obscure ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: const Color(0xFF6B7280),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.tonalIcon(
        onPressed: _loading ? null : _signInWithBiometric,
        style: FilledButton.styleFrom(
          backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.12),
          foregroundColor: HexaColors.brandPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.fingerprint, size: 28),
        label: const Text(
          'Sign in with fingerprint / Face ID',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _loading
            ? null
            : (_isFormValid
                ? _signIn
                : () => setState(() => _showValidation = true)),
        style: FilledButton.styleFrom(
          backgroundColor: HexaColors.brandPrimary,
          disabledBackgroundColor: const Color(0xFFE5E7EB),
          disabledForegroundColor: const Color(0xFF6B7280),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: HexaColors.brandPrimary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Sign In'),
      ),
    );
  }
}
