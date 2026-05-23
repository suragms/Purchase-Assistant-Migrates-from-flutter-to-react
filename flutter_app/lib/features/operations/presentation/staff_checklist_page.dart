import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/operations_providers.dart';
import '../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../core/providers/warehouse_alerts_provider.dart';
import '../../../core/widgets/friendly_load_error.dart';

class StaffChecklistPage extends ConsumerStatefulWidget {
  const StaffChecklistPage({super.key});

  @override
  ConsumerState<StaffChecklistPage> createState() => _StaffChecklistPageState();
}

class _StaffChecklistPageState extends ConsumerState<StaffChecklistPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Set<String> _busy = {};
  final Set<String> _optimisticDone = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _completeTask({
    required String slot,
    required Map<String, dynamic> task,
  }) async {
    if (task['completed'] == true) return;
    final key = task['task_key']?.toString() ?? '';
    if (key.isEmpty) return;
    final busyId = '$slot:$key';
    if (_busy.contains(busyId)) return;
    setState(() {
      _busy.add(busyId);
      _optimisticDone.add(busyId);
    });
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      await ref.read(hexaApiProvider).completeChecklistTask(
            businessId: session.primaryBusiness.id,
            slot: slot,
            taskKey: key,
          );
      ref.invalidate(checklistTodayProvider);
      ref.invalidate(warehouseAlertsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) setState(() {});
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        ref.invalidate(checklistTodayProvider);
        return;
      }
      if (mounted) {
        setState(() => _optimisticDone.remove(busyId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(busyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(checklistTodayProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Daily checklist'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Morning'),
            Tab(text: 'Midday'),
            Tab(text: 'Evening'),
          ],
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyLoadError(
          onRetry: () => ref.invalidate(checklistTodayProvider),
        ),
        data: (m) {
          final tasks = [
            for (final t in (m['tasks'] as List? ?? []))
              if (t is Map) Map<String, dynamic>.from(t),
          ];
          final total = tasks.length;
          final doneCount = tasks.where((t) {
            final key = t['task_key']?.toString() ?? '';
            final slot = t['slot']?.toString() ?? '';
            final busyId = '$slot:$key';
            return t['completed'] == true || _optimisticDone.contains(busyId);
          }).length;
          final pct = total > 0 ? doneCount / total * 100 : 0.0;
          return Column(
            children: [
              LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                color: const Color(0xFF3B6D11),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  total > 0
                      ? '$doneCount/$total complete · ${pct.toStringAsFixed(0)}%'
                      : '${pct.toStringAsFixed(0)}% complete today',
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _slotList(context, tasks, 'morning'),
                    _slotList(context, tasks, 'midday'),
                    _slotList(context, tasks, 'evening'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _slotList(
    BuildContext context,
    List<Map<String, dynamic>> tasks,
    String slot,
  ) {
    final slotTasks = tasks.where((t) => t['slot'] == slot).toList();
    if (slotTasks.isEmpty) {
      final low = ref.watch(stockLowTopHomeProvider).valueOrNull ?? [];
      if (low.isNotEmpty) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Suggested checks (low stock)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final row in low.take(3))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(row['name']?.toString() ?? 'Item'),
                  subtitle: Text(
                    'Stock ${row['current_stock'] ?? '—'}',
                  ),
                ),
          ],
        );
      }
      return const Center(child: Text('No tasks for this shift'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: slotTasks.length,
      itemBuilder: (ctx, i) {
        final t = slotTasks[i];
        final key = t['task_key']?.toString() ?? '';
        final busyId = '$slot:$key';
        final done =
            t['completed'] == true || _optimisticDone.contains(busyId);
        final busy = _busy.contains(busyId);
        return CheckboxListTile(
          value: done,
          tristate: false,
          onChanged: done || busy
              ? null
              : (v) {
                  if (v == true) {
                    _completeTask(slot: slot, task: t);
                  }
                },
          title: Text(t['label']?.toString() ?? ''),
          secondary: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        );
      },
    );
  }
}
