// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utilities for haptic feedback
class HapticUtil {
  /// Feedback
  Future<void> feedback() async {
    if (!kIsWeb) {
      await HapticFeedback.vibrate();
    }
  }
  
  /// Light feedback
  static Future<void> lightFeedback() async {
    if (!kIsWeb) {
      await HapticFeedback.lightImpact();
    }
  }
  
  /// Medium feedback
  static Future<void> mediumFeedback() async {
    if (!kIsWeb) {
      await HapticFeedback.mediumImpact();
    }
  }
  
  /// Heavy feedback
  static Future<void> heavyFeedback() async {
    if (!kIsWeb) {
      await HapticFeedback.heavyImpact();
    }
  }
}
