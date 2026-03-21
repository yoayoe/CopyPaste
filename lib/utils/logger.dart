import 'package:flutter/foundation.dart';

class Log {
  Log._();

  static void d(String tag, String message) {
    debugPrint('[$tag] $message');
  }

  static void i(String tag, String message) {
    debugPrint('[$tag] $message');
  }

  static void w(String tag, String message) {
    debugPrint('[$tag] ⚠ $message');
  }

  static void e(String tag, String message, [Object? error]) {
    debugPrint('[$tag] ✖ $message${error != null ? ': $error' : ''}');
  }
}
