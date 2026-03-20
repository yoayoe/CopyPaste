import 'dart:developer' as dev;

class Log {
  Log._();

  static void d(String tag, String message) {
    dev.log('[$tag] $message', level: 0);
  }

  static void i(String tag, String message) {
    dev.log('[$tag] $message', level: 800);
  }

  static void w(String tag, String message) {
    dev.log('[$tag] ⚠ $message', level: 900);
  }

  static void e(String tag, String message, [Object? error]) {
    dev.log('[$tag] ✖ $message', level: 1000, error: error);
  }
}
