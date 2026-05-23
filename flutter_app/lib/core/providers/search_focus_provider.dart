import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Staff home search button sets this so [SearchPage] auto-focuses the field.
final searchFocusRequestedProvider = StateProvider<bool>((ref) => false);
