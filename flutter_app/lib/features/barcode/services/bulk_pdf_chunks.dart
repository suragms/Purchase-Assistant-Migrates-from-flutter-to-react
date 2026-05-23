import '../services/barcode_pdf_service.dart';

/// A4 sheet: labels per page (one PDF, multiple pages).
/// Thermal roll: max labels per output PDF when splitting.
enum BulkLabelsPerPdfFile {
  n30(30),
  n40(40),
  n50(50),
  n60(60);

  const BulkLabelsPerPdfFile(this.count);
  final int count;
}

/// Expand [items] with [copiesPerItem] then split into chunks of at most [perFile].
List<List<BarcodeLabelData>> chunkExpandedLabelsForPdfFiles({
  required List<BarcodeLabelData> items,
  required int copiesPerItem,
  required int perFile,
}) {
  if (items.isEmpty || perFile < 1) return [];
  final expanded = <BarcodeLabelData>[];
  final copies = copiesPerItem.clamp(1, 5);
  for (final data in items) {
    for (var c = 0; c < copies; c++) {
      expanded.add(data);
    }
  }
  final chunks = <List<BarcodeLabelData>>[];
  for (var i = 0; i < expanded.length; i += perFile) {
    final end = i + perFile > expanded.length ? expanded.length : i + perFile;
    chunks.add(expanded.sublist(i, end));
  }
  return chunks;
}
