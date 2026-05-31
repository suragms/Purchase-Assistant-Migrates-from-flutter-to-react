import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';

Future<bool> showStaffVerificationSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String purchaseId,
  required List<Map<String, dynamic>> lines,
}) async {
  final ok = await showHexaBottomSheet<bool>(
    context: context,
    compact: false,
    padding: EdgeInsets.zero,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: HexaResponsive.adaptiveSheetMaxHeight(context),
      ),
      child: _StaffVerificationSheet(
        purchaseId: purchaseId,
        lines: lines,
      ),
    ),
  );
  return ok == true;
}

class _StaffVerificationSheet extends ConsumerStatefulWidget {
  const _StaffVerificationSheet({
    required this.purchaseId,
    required this.lines,
  });

  final String purchaseId;
  final List<Map<String, dynamic>> lines;

  @override
  ConsumerState<_StaffVerificationSheet> createState() => _StaffVerificationSheetState();
}

class _StaffVerificationSheetState extends ConsumerState<_StaffVerificationSheet> {
  final _notesCtrl = TextEditingController();
  final _received = <String, TextEditingController>{};
  final _damaged = <String, TextEditingController>{};
  final _returned = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final row in widget.lines) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final qty = coerceToDouble(row['qty']);
      final unit = row['unit']?.toString() ?? row['stock_unit']?.toString() ?? 'piece';
      _received[id] = TextEditingController(
        text: qty > 0 ? formatStockQtyForUnit(unit, qty) : '',
      );
      _damaged[id] = TextEditingController();
      _returned[id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _received.values) {
      c.dispose();
    }
    for (final c in _damaged.values) {
      c.dispose();
    }
    for (final c in _returned.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    final payload = <Map<String, dynamic>>[];
    for (final row in widget.lines) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final r = double.tryParse((_received[id]?.text ?? '').trim()) ?? 0;
      final d = double.tryParse((_damaged[id]?.text ?? '').trim()) ?? 0;
      final rr = double.tryParse((_returned[id]?.text ?? '').trim()) ?? 0;
      payload.add({
        'line_id': id,
        'received_qty': r,
        'damaged_qty': d,
        'return_qty': rr,
      });
    }
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).verifyPurchaseDelivery(
            businessId: session.primaryBusiness.id,
            purchaseId: widget.purchaseId,
            lines: payload,
            notes: _notesCtrl.text,
          );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Staff Verification',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final row in widget.lines) ...[
              _lineRow(row),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: const Text('SUBMIT VERIFICATION'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['item_name']?.toString() ?? 'Item';
    final unit = row['unit']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _numField(_received[id], 'Received', unit)),
              const SizedBox(width: 8),
              Expanded(child: _numField(_damaged[id], 'Damaged', unit)),
              const SizedBox(width: 8),
              Expanded(child: _numField(_returned[id], 'Return', unit)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController? c, String label, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.toUpperCase(),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

