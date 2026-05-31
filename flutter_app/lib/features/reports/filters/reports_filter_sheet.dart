import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/theme/hexa_colors.dart';
import '../filters/reports_filter_state.dart';

/// Mobile filter bottom sheet.
Future<void> showReportsFilterSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  return showHexaBottomSheet<void>(
    context: context,
    child: _ReportsFilterSheetBody(ref: ref),
  );
}

class _ReportsFilterSheetBody extends ConsumerStatefulWidget {
  const _ReportsFilterSheetBody({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_ReportsFilterSheetBody> createState() =>
      _ReportsFilterSheetBodyState();
}

class _ReportsFilterSheetBodyState
    extends ConsumerState<_ReportsFilterSheetBody> {
  late ReportsFilterState _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(reportsFilterProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filters',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          const Text(
            'Unit',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in ReportsUnitFilter.values)
                FilterChip(
                  label: Text(u.name.toUpperCase()),
                  selected: _draft.units.contains(u),
                  onSelected: (sel) {
                    setState(() {
                      if (u == ReportsUnitFilter.all) {
                        _draft = _draft.copyWith(
                          units: sel ? {ReportsUnitFilter.all} : {},
                        );
                      } else {
                        final next = Set<ReportsUnitFilter>.from(_draft.units)
                          ..remove(ReportsUnitFilter.all);
                        if (sel) {
                          next.add(u);
                        } else {
                          next.remove(u);
                        }
                        if (next.isEmpty) next.add(ReportsUnitFilter.all);
                        _draft = _draft.copyWith(units: next);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Sort',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in ReportsSort.values)
                FilterChip(
                  label: Text(s.name),
                  selected: _draft.sort == s,
                  onSelected: (_) =>
                      setState(() => _draft = _draft.copyWith(sort: s)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(reportsFilterProvider.notifier).reset();
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref.read(reportsFilterProvider.notifier).apply(_draft);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tablet/desktop right drawer filter panel.
class ReportsFilterDrawer extends ConsumerWidget {
  const ReportsFilterDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(reportsFilterProvider);
    return Material(
      color: HexaColors.brandCard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Filters',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '${filters.activeCount} active',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () =>
                showReportsFilterSheet(context: context, ref: ref),
            child: const Text('Edit filters'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.read(reportsFilterProvider.notifier).reset(),
            child: const Text('Reset all'),
          ),
        ],
      ),
    );
  }
}
