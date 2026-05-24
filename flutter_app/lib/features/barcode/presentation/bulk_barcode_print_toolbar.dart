import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/widgets/operational_async_button.dart';
import '../services/bulk_pdf_chunks.dart';

class BulkBarcodePrintToolbar extends StatelessWidget {
  const BulkBarcodePrintToolbar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.denseA4,
    required this.useQr,
    required this.copies,
    required this.labelsPerPdfFile,
    required this.progress,
    required this.statusText,
    required this.onDenseA4Changed,
    required this.onQrChanged,
    required this.onCopiesChanged,
    required this.onLabelsPerPdfFileChanged,
    required this.onPreview,
    required this.onPdf,
    required this.onPrint,
    this.pdfButtonLabel = 'PDF',
  });

  final int selectedCount;
  final bool busy;
  final bool denseA4;
  final bool useQr;
  final int copies;
  final BulkLabelsPerPdfFile labelsPerPdfFile;
  final double? progress;
  final String? statusText;
  final ValueChanged<bool> onDenseA4Changed;
  final ValueChanged<bool> onQrChanged;
  final ValueChanged<int> onCopiesChanged;
  final ValueChanged<BulkLabelsPerPdfFile> onLabelsPerPdfFileChanged;
  final Future<void> Function() onPreview;
  final Future<void> Function() onPdf;
  final Future<void> Function() onPrint;
  final String pdfButtonLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !busy;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HexaOp.pageGutter,
            6,
            HexaOp.pageGutter,
            6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress != null || statusText != null) ...[
                LinearProgressIndicator(minHeight: 2, value: progress),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      statusText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FmtChip(
                      label: denseA4 ? 'A4' : 'Thermal',
                      selected: denseA4,
                      onTap: busy ? null : () => onDenseA4Changed(!denseA4),
                    ),
                    const SizedBox(width: 4),
                    _FmtChip(
                      label: useQr ? 'QR' : 'Code128',
                      selected: !useQr,
                      onTap: busy ? null : () => onQrChanged(!useQr),
                    ),
                    const SizedBox(width: 4),
                    _CopiesChip(
                      value: copies,
                      enabled: !busy,
                      onChanged: onCopiesChanged,
                    ),
                    if (denseA4) ...[
                      const SizedBox(width: 4),
                      _FmtChip(
                        label: '${labelsPerPdfFile.count}/pg',
                        selected: true,
                        onTap: busy
                            ? null
                            : () {
                                final next = switch (labelsPerPdfFile) {
                                  BulkLabelsPerPdfFile.n30 =>
                                    BulkLabelsPerPdfFile.n50,
                                  BulkLabelsPerPdfFile.n50 =>
                                    BulkLabelsPerPdfFile.n60,
                                  _ => BulkLabelsPerPdfFile.n30,
                                };
                                onLabelsPerPdfFileChanged(next);
                              },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OperationalAsyncButton(
                      label: 'Preview',
                      icon: Icons.visibility_outlined,
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPreview : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OperationalAsyncButton(
                      label: pdfButtonLabel,
                      icon: Icons.download_outlined,
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPdf : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OperationalAsyncButton(
                      label: 'Print',
                      icon: Icons.print_outlined,
                      filled: true,
                      busy: busy,
                      enabled: enabled,
                      onPressed: enabled ? onPrint : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FmtChip extends StatelessWidget {
  const _FmtChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _CopiesChip extends StatelessWidget {
  const _CopiesChip({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniIconBtn(
            icon: Icons.remove,
            enabled: enabled && value > 1,
            onTap: () => onChanged(value - 1),
          ),
          Text(
            '×$value',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          _MiniIconBtn(
            icon: Icons.add,
            enabled: enabled && value < 5,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _MiniIconBtn extends StatelessWidget {
  const _MiniIconBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(icon),
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}
