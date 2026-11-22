// lib/utils/haptics.dart
// Simple wrapper around Flutter's HapticFeedback. No-ops on web/desktop.

import 'package:flutter/services.dart';

class Haptics {
  Haptics._();

  static Future<void> light() => HapticFeedback.lightImpact();
  static Future<void> medium() => HapticFeedback.mediumImpact();
  static Future<void> heavy() => HapticFeedback.heavyImpact();
  static Future<void> selection() => HapticFeedback.selectionClick();
}
