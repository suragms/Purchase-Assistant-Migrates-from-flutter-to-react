import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

class DailyUsagePage extends ConsumerStatefulWidget {
  const DailyUsagePage({super.key});

  @override
  ConsumerState<DailyUsagePage> createState() => _DailyUsagePageState();
}

class _DailyUsagePageState extends ConsumerState<DailyUsagePage> {
  final _used = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _used.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(usageTodayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Log today\'s usage')),
      body: usage.when(
        loading: () => const ListSkeleton(rowCount: 6),
        error: (e, _) => FriendlyLoadError(
          onRetry: () => ref.invalidate(usageTodayProvider),
        ),
        data: (data) {
          final rawLines = data['lines'] ??
              data['items'] ??
              data['usage_lines'] ??
              data['data'] ??
              [];
          final lines = [
            for (final e in (rawLines as List? ?? []))
              if (e is Map) Map<String, dynamic>.from(e),
          ];
          if (lines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 48, color: Colors.green),
                    SizedBox(height: 12),
                    Text(
                      'Nothing to log today',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All items are up to date',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }
          for (final line in lines) {
            final id = line['item_id']?.toString() ?? '';
            _used.putIfAbsent(
              id,
              () => TextEditingController(
                text: line['logged'] == true
                    ? (line['used_qty']?.toString() ?? '0')
                    : '',
              ),
            );
          }
          return Column(
            children: [
              if ((data['missing_count'] as num? ?? 0) > 0)
                Material(
                  color: const Color(0xFFFFF3E0),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(
                      '${data['missing_count']} items still need usage logged',
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: lines.length,
                  itemBuilder: (ctx, i) {
                    final line = lines[i];
                    final id = line['item_id']?.toString() ?? '';
                    final unit = line['unit']?.toString() ?? '';
                    final opening = (line['opening_qty'] as num?)?.toDouble() ?? 0;
                    final purchased = (line['purchased_qty'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      title: Text(line['item_name']?.toString() ?? ''),
                      subtitle: Text(
                        'Open ${stockDisplayPrimary(opening, unit)} · '
                        'Bought ${stockDisplayPrimary(purchased, unit)}',
                      ),
                      trailing: SizedBox(
                        width: 72,
                        child: TextField(
                          controller: _used[id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Used',
                            isDense: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(lines),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save usage'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(List<Map<String, dynamic>> lines) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final payload = <Map<String, dynamic>>[];
      for (final line in lines) {
        final id = line['item_id']?.toString() ?? '';
        final raw = _used[id]?.text.trim() ?? '';
        if (raw.isEmpty) continue;
        final used = double.tryParse(raw);
        if (used == null || used < 0) continue;
        payload.add({'item_id': id, 'used_qty': used});
      }
      if (payload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter used quantity for at least one item')),
          );
        }
        return;
      }
      await ref.read(hexaApiProvider).submitUsageToday(
            businessId: session.primaryBusiness.id,
            lines: payload,
          );
      ref.invalidate(usageTodayProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usage saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
