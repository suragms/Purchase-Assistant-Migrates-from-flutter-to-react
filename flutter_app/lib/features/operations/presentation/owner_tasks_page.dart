import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/operations_providers.dart';

final ownerChecklistSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider);
  if (s == null) return {};
  return ref.read(hexaApiProvider).getChecklistSummary(
        businessId: s.primaryBusiness.id,
      );
});

class OwnerTasksPage extends ConsumerStatefulWidget {
  const OwnerTasksPage({super.key});

  @override
  ConsumerState<OwnerTasksPage> createState() => _OwnerTasksPageState();
}

class _OwnerTasksPageState extends ConsumerState<OwnerTasksPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final List<_EditableTask> _draft = [];
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final t in _draft) {
      t.labelCtrl.dispose();
    }
    super.dispose();
  }

  void _loadDraft(List<Map<String, dynamic>> rows) {
    for (final t in _draft) {
      t.labelCtrl.dispose();
    }
    _draft.clear();
    for (final r in rows) {
      _draft.add(
        _EditableTask(
          slot: r['slot']?.toString() ?? 'morning',
          taskKey: r['task_key']?.toString() ?? '',
          labelCtrl: TextEditingController(text: r['label']?.toString() ?? ''),
          sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    _dirty = false;
  }

  Future<void> _saveTemplates() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final tasks = <Map<String, dynamic>>[];
    for (var i = 0; i < _draft.length; i++) {
      final t = _draft[i];
      final label = t.labelCtrl.text.trim();
      if (label.isEmpty) continue;
      tasks.add({
        'slot': t.slot,
        if (t.taskKey.isNotEmpty) 'task_key': t.taskKey,
        'label': label,
        'sort_order': i + 1,
      });
    }
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one task')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).putChecklistTemplates(
            businessId: session.primaryBusiness.id,
            tasks: tasks,
          );
      ref.invalidate(checklistTemplatesProvider);
      ref.invalidate(checklistTodayProvider);
      ref.invalidate(ownerChecklistSummaryProvider);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff task list saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addTask(String slot) {
    setState(() {
      _draft.add(
        _EditableTask(
          slot: slot,
          taskKey: '',
          labelCtrl: TextEditingController(),
          sortOrder: _draft.length + 1,
        ),
      );
      _dirty = true;
    });
  }

  Future<void> _completeOwnTask(Map<String, dynamic> task) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final slot = task['slot']?.toString() ?? '';
    final key = task['task_key']?.toString() ?? '';
    if (slot.isEmpty || key.isEmpty || task['completed'] == true) return;
    try {
      await ref.read(hexaApiProvider).completeChecklistTask(
            businessId: session.primaryBusiness.id,
            slot: slot,
            taskKey: key,
          );
      ref.invalidate(checklistTodayProvider);
      ref.invalidate(ownerChecklistSummaryProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    final todayAsync = ref.watch(checklistTodayProvider);
    final summary = ref.watch(ownerChecklistSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff tasks'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Arrange list'),
            Tab(text: 'Check today'),
          ],
        ),
        actions: [
          if (_tabs.index == 0 && _dirty)
            TextButton(
              onPressed: _saving ? null : _saveTemplates,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _arrangeTab(templatesAsync),
          _checkTodayTab(todayAsync, summary),
        ],
      ),
    );
  }

  Widget _arrangeTab(AsyncValue<List<Map<String, dynamic>>> templatesAsync) {
    return templatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyApiError(e))),
      data: (rows) {
        if (!_dirty && _draft.isEmpty && rows.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _loadDraft(rows));
          });
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'These tasks appear on every staff phone (Morning / Midday / Evening).',
              style: HexaDsType.bodySm(context),
            ),
            const SizedBox(height: 12),
            for (final slot in const ['morning', 'midday', 'evening']) ...[
              Row(
                children: [
                  Text(
                    slot[0].toUpperCase() + slot.substring(1),
                    style: HexaDsType.heading(16),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addTask(slot),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              ..._draft
                  .where((t) => t.slot == slot)
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: t.labelCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Task label',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() => _dirty = true),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () {
                              setState(() {
                                t.labelCtrl.dispose();
                                _draft.remove(t);
                                _dirty = true;
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _saving || !_dirty ? null : _saveTemplates,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save task list for all staff'),
            ),
          ],
        );
      },
    );
  }

  Widget _checkTodayTab(
    AsyncValue<Map<String, dynamic>> todayAsync,
    AsyncValue<Map<String, dynamic>> summary,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        summary.when(
          data: (s) => Card(
            child: ListTile(
              title: Text(
                'Team progress ${((s['completion_pct'] as num?) ?? 0).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Completed ${(s['tasks_completed'] as num?)?.toInt() ?? 0} / '
                '${(s['tasks_total'] as num?)?.toInt() ?? 0} task keys today',
              ),
            ),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        Text('Your checklist today', style: HexaDsType.heading(16)),
        const SizedBox(height: 8),
        todayAsync.when(
          data: (d) {
            final tasks = [
              for (final e in (d['tasks'] as List? ?? const []))
                if (e is Map) Map<String, dynamic>.from(e),
            ];
            if (tasks.isEmpty) {
              return const Text('No tasks — save a list in Arrange tab');
            }
            return Column(
              children: [
                for (final t in tasks)
                  Card(
                    child: CheckboxListTile(
                      value: t['completed'] == true,
                      onChanged: t['completed'] == true
                          ? null
                          : (_) => _completeOwnTask(t),
                      title: Text(t['label']?.toString() ?? 'Task'),
                      subtitle: Text(
                        (t['slot']?.toString() ?? '').toUpperCase(),
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text(friendlyApiError(e)),
        ),
      ],
    );
  }
}

class _EditableTask {
  _EditableTask({
    required this.slot,
    required this.taskKey,
    required this.labelCtrl,
    required this.sortOrder,
  });

  final String slot;
  final String taskKey;
  final TextEditingController labelCtrl;
  final int sortOrder;
}
