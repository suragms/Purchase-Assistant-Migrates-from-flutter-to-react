import 'package:flutter/services.dart';

/// Uppercase internal item codes: A-Z, 0-9, hyphen, underscore; no spaces.
class ItemCodeInputFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'[A-Za-z0-9_-]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buf = StringBuffer();
    for (final ch in newValue.text.split('')) {
      if (_allowed.hasMatch(ch)) {
        buf.write(ch.toUpperCase());
      }
    }
    final t = buf.toString();
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

String normalizeItemCode(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

bool isValidItemCode(String code) =>
    RegExp(r'^[A-Z0-9_-]+$').hasMatch(code) && code.isNotEmpty;
