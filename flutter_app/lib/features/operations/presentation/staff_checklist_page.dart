import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/operations_providers.dart';

class StaffChecklistPage extends ConsumerStatefulWidget {
  const StaffChecklistPage({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

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
      if (session == null) {
        throw DioException(
          requestOptions: RequestOptions(path: '/checklist'),
          type: DioExceptionType.cancel,
        );
      }
      await ref.read(hexaApiProvider).completeChecklistTask(
            businessId: session.primaryBusiness.id,
            slot: slot,
            taskKey: key,
          );
      ref.invalidate(checklistTodayProvider);
      await ref.read(checklistTodayProvider.future);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _optimisticDone.remove(busyId));
        if (e.response?.statusCode != 409) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(friendlyApiError(e)),
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          ref.invalidate(checklistTodayProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticDone.remove(busyId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(busyId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(checklistTodayProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embeddedInShell,
        leading: widget.embeddedInShell
            ? null
            : BackButton(onPressed: () => context.pop()),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My tasks'),
            Text(
              'Complete these first',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
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
        error: (e, _) {
          final msg = e is DioException
              ? friendlyApiError(e)
              : 'Could not load tasks. Pull to refresh or sign in again.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(msg, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(checklistTodayProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
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
                value: total > 0 ? (pct / 100).clamp(0.0, 1.0) : 0,
                color: const Color(0xFF0E4F46),
                backgroundColor: const Color(0xFFE2E8F0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        total > 0
                            ? '$doneCount / $total complete · ${pct.toStringAsFixed(0)}%'
                            : 'No tasks configured',
                        style: HexaDsType.label(13),
                      ),
                    ),
                    if (total > 0)
                      Text(
                        'Midday & Evening tabs →',
                        style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                      ),
                  ],
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
      return Center(
        child: Text(
          'No $slot tasks — ask owner to add tasks in Settings → Owner tasks',
          textAlign: TextAlign.center,
          style: HexaDsType.body(14, color: HexaDsColors.textMuted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(checklistTodayProvider);
        await ref.read(checklistTodayProvider.future);
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        itemCount: slotTasks.length,
        itemBuilder: (ctx, i) {
          final t = slotTasks[i];
          final key = t['task_key']?.toString() ?? '';
          final busyId = '$slot:$key';
          final done =
              t['completed'] == true || _optimisticDone.contains(busyId);
          final busy = _busy.contains(busyId);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: CheckboxListTile(
              value: done,
              onChanged: done || busy
                  ? null
                  : (v) {
                      if (v == true) {
                        _completeTask(slot: slot, task: t);
                      }
                    },
              title: Text(
                t['label']?.toString() ?? '',
                style: TextStyle(
                  fontWeight: done ? FontWeight.w600 : FontWeight.w800,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
              secondary: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      done ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: done
                          ? const Color(0xFF0E4F46)
                          : const Color(0xFF94A3B8),
                    ),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          );
        },
      ),
    );
  }
}
