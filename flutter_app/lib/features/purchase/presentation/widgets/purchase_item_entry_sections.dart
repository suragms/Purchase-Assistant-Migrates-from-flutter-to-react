import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../../../core/pricing/tax_mode.dart';

/// Landing + selling rate row for [PurchaseItemEntrySheet] (isolated rebuild scope).
class PurchaseItemEntryRateSection extends StatelessWidget {
  const PurchaseItemEntryRateSection({
    super.key,
    required this.showPerKgFields,
    required this.landingCtrl,
    required this.sellingCtrl,
    required this.landingFocus,
    required this.sellingFocus,
    required this.landingKey,
    required this.sellingKey,
    required this.landingLabel,
    required this.sellingLabel,
    required this.errLanding,
    required this.errSelling,
    required this.decimalFormatter,
    required this.textFieldScrollPadding,
    required this.deco,
    required this.onFieldChanged,
    required this.preferVertical,
  });

  final bool showPerKgFields;
  final TextEditingController landingCtrl;
  final TextEditingController sellingCtrl;
  final FocusNode landingFocus;
  final FocusNode sellingFocus;
  final GlobalKey landingKey;
  final GlobalKey sellingKey;
  final String landingLabel;
  final String sellingLabel;
  final String? errLanding;
  final String? errSelling;
  final TextInputFormatter Function(int) decimalFormatter;
  final EdgeInsets Function() textFieldScrollPadding;
  final InputDecoration Function(String label, {String? prefixText, String? errorText}) deco;
  final VoidCallback onFieldChanged;
  final bool preferVertical;

  @override
  Widget build(BuildContext context) {
    Widget landingField() => KeyedSubtree(
          key: landingKey,
          child: TextField(
            controller: landingCtrl,
            focusNode: landingFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalFormatter(2)],
            textInputAction: TextInputAction.next,
            scrollPadding: textFieldScrollPadding(),
            decoration: deco(
              landingLabel,
              prefixText: '₹ ',
              errorText: errLanding,
            ),
            onChanged: (_) => onFieldChanged(),
            onSubmitted: (_) => FocusScope.of(context).requestFocus(sellingFocus),
          ),
        );

    Widget sellingField() => KeyedSubtree(
          key: sellingKey,
          child: TextField(
            controller: sellingCtrl,
            focusNode: sellingFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalFormatter(2)],
            textInputAction: TextInputAction.done,
            scrollPadding: textFieldScrollPadding(),
            decoration: deco(
              sellingLabel,
              prefixText: '₹ ',
              errorText: errSelling,
            ),
            onChanged: (_) => onFieldChanged(),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        const narrowBreak = 300.0;
        const minPairWidth = 280.0;
        final stack = preferVertical || constraints.maxWidth < minPairWidth;
        if (stack || constraints.maxWidth < narrowBreak) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              landingField(),
              const SizedBox(height: 10),
              sellingField(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: landingField()),
            const SizedBox(width: 6),
            Expanded(flex: 5, child: sellingField()),
          ],
        );
      },
    );
  }
}

/// Tax mode chips for purchase item entry.
class PurchaseItemEntryTaxSection extends StatelessWidget {
  const PurchaseItemEntryTaxSection({
    super.key,
    required this.taxMode,
    required this.onPick,
  });

  final TaxMode taxMode;
  final Future<void> Function(TaxMode) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String chipLabel(TaxMode m) => switch (m) {
          TaxMode.exclusive => 'Excl GST',
          TaxMode.inclusive => 'Incl GST',
          TaxMode.none => 'No GST',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tax mode',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final m in TaxMode.values)
              FilterChip(
                selected: taxMode == m,
                label: Text(chipLabel(m)),
                showCheckmark: false,
                onSelected: (_) => onPick(m),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Exclusive adds GST on the line base. Inclusive treats your rate as GST-included. None clears GST.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.hintColor,
          ),
        ),
      ],
    );
  }
}

/// Compact live totals footer used when keyboard is visible.
class PurchaseItemEntryKeyboardTotals extends StatelessWidget {
  const PurchaseItemEntryKeyboardTotals({
    super.key,
    required this.totalLabel,
    required this.profitLabel,
    required this.netTaxLabel,
    required this.qtySummary,
  });

  final String totalLabel;
  final String profitLabel;
  final String netTaxLabel;
  final String qtySummary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              totalLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              profitLabel,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
              ),
            ),
            Text(
              netTaxLabel,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            qtySummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}
