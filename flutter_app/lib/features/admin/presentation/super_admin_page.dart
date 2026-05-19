import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/router/navigation_ext.dart';

final _superAdminHealthProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(hexaApiProvider).superAdminHealth();
});

final _superAdminBizProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(hexaApiProvider).superAdminBusinessesOverview(limit: 80);
});

/// JWT super-admin tools (wired to `/v1/admin/health` + businesses overview).
class SuperAdminPage extends ConsumerWidget {
  const SuperAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final health = ref.watch(_superAdminHealthProvider);
    final biz = ref.watch(_superAdminBizProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1419),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1419),
        foregroundColor: Colors.white,
        title: Text('Super admin',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_superAdminHealthProvider);
              ref.invalidate(_superAdminBizProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('System health',
              style: tt.titleMedium?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          health.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => _AdminErrorCard(
                  message: userFacingError(e),
                ),
            data: (m) => _AdminKvCard(data: m, accent: const Color(0xFF17A8A7)),
          ),
          const SizedBox(height: 24),
          Text('Businesses (overview)',
              style: tt.titleMedium?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          biz.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => _AdminErrorCard(
                  message: userFacingError(e),
                ),
            data: (m) {
              final items = m['items'];
              if (items is! List || items.isEmpty) {
                return const Text(
                  'No businesses returned.',
                  style: TextStyle(color: Colors.white54),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final raw in items.take(20))
                    if (raw is Map)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AdminBizTile(
                          name: raw['name']?.toString() ?? '—',
                          id: raw['id']?.toString() ?? '',
                          meta: raw['plan']?.toString(),
                        ),
                      ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: () {
              ref.invalidate(_superAdminHealthProvider);
              ref.invalidate(_superAdminBizProvider);
            },
            icon: const Icon(Icons.cached_rounded),
            label: const Text('Reload all'),
          ),
        ],
      ),
    );
  }
}

class _AdminKvCard extends StatelessWidget {
  const _AdminKvCard({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String, String>>[];
    void flatten(String prefix, dynamic value) {
      if (value is Map) {
        for (final e in value.entries) {
          final key = prefix.isEmpty ? e.key.toString() : '$prefix.${e.key}';
          flatten(key, e.value);
        }
      } else if (value is List) {
        entries.add(MapEntry(prefix, '${value.length} items'));
      } else {
        entries.add(MapEntry(prefix, value?.toString() ?? '—'));
      }
    }

    flatten('', data);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i < entries.length - 1
                    ? const Border(
                        bottom: BorderSide(color: Color(0xFF2A3544)),
                      )
                    : null,
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  entries[i].key,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  entries[i].value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminBizTile extends StatelessWidget {
  const _AdminBizTile({
    required this.name,
    required this.id,
    this.meta,
  });

  final String name;
  final String id;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A222C),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        title: Text(name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          meta != null && meta!.isNotEmpty ? '$id · $meta' : id,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    );
  }
}

class _AdminErrorCard extends StatelessWidget {
  const _AdminErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3B1F1F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFFFCDD2))),
    );
  }
}
