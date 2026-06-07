import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_failure_policy.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/theme/hexa_colors.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  bool _busy = true;
  String? _error;
  bool _warmupRetried = false;

  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).restore().timeout(
            kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 25),
          );
    } catch (_) {
      if (!_warmupRetried && mounted) {
        _warmupRetried = true;
        setState(() {
          _busy = true;
          _error = 'Server is warming up. Retrying in 10 seconds…';
        });
        await Future<void>.delayed(const Duration(seconds: 10));
        if (mounted) return _boot();
      }
      // Timeout / offline — continue to token check below.
    }
    if (!mounted) return;
    final expired = ref.read(authSessionExpiredProvider) ||
        ref.read(auth401CircuitOpenProvider);
    final s = ref.read(sessionProvider);
    if (s != null) {
      context.go(authenticatedHomePath(s));
      return;
    }
    if (expired) {
      await ref.read(sessionProvider.notifier).logout();
      if (mounted) context.go('/login?notice=session_expired');
      return;
    }
    ({String? access, String? refresh}) t;
    try {
      t = await ref.read(tokenStoreProvider).read();
    } catch (_) {
      if (mounted) context.go('/login');
      return;
    }
    if (t.access != null && t.refresh != null) {
      setState(() {
        _busy = false;
        _error =
            "We couldn't refresh your session. Check your connection and tap Retry.";
      });
      return;
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HexaColors.brandPrimary,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF062E28),
                  Color(0xFF0E4F46),
                  Color(0xFF159A8A),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.warehouse_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    HexaColors.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    HexaColors.appTagline,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_busy)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : _boot,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Use another account'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            left: 0,
            right: 0,
            child: Text(
              '${HexaColors.appName} v1.0',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
