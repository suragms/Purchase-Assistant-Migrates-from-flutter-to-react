import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import 'widgets/auth_input_styles.dart';
import 'widgets/auth_network_error_banner.dart';
import 'widgets/auth_page_shell.dart';

/// Keyboard-safe, centered card login (no hero image) — iOS + web friendly.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
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

  @override
  void initState() {
    super.initState();
    _loginEmail.addListener(_clearInlineErrors);
    _loginPass.addListener(_clearInlineErrors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryResumeSession();
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
        if (notice == 'owner_only') {
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
    _loginEmail.removeListener(_clearInlineErrors);
    _loginPass.removeListener(_clearInlineErrors);
    _loginEmail.dispose();
    _loginPass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    final id = _loginEmail.text.trim();
    final p = _loginPass.text;
    return id.length >= 3 && p.length >= 6;
  }

  String? _identifierError() {
    if (!_showValidation) return null;
    final s = _loginEmail.text.trim();
    if (s.isEmpty || s.length < 3) {
      return 'Enter username or phone (min 3 characters)';
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
      await ref.read(sessionProvider.notifier).login(
            identifier: _loginEmail.text.trim(),
            password: _loginPass.text,
          );
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
          _inlineAuthError = 'Wrong username, phone, or password. Try again.';
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

  @override
  Widget build(BuildContext context) {
    final eErr = _identifierError();
    final pErr = _passError();

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5F2),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AuthPageShell(
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
                        const SizedBox(width: HexaDsLayout.inlineGap),
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
                    const SizedBox(height: HexaDsLayout.blockGap),
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
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: authFilledDecoration(
                        'Username or phone',
                        icon: Icons.person_outline_rounded,
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
        ),
      ),
    );
  }
}
