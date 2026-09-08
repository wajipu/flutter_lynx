typedef LynxLogCallback = void Function(String tag, String message, {Object? error});

/// Centralized logger for the flutter_lynx plugin.
class LynxLogger {
  static LynxLogCallback? onLog;
  static bool enablePrint = true;

  static void info(String tag, String message) {
    final formatted = "[Lynx][$tag] $message";
    if (enablePrint) {
      // ignore: avoid_print
      print(formatted);
    }
    onLog?.call(tag, message);
  }

  static void warn(String tag, String message, [Object? error]) {
    final formatted = "[Lynx][$tag][WARN] $message${error != null ? ': $error' : ''}";
    if (enablePrint) {
      // ignore: avoid_print
      print(formatted);
    }
    onLog?.call(tag, message, error: error);
  }

  static void error(String tag, String message, [Object? error]) {
    final formatted = "[Lynx][$tag][ERROR] $message${error != null ? ': $error' : ''}";
    if (enablePrint) {
      // ignore: avoid_print
      print(formatted);
    }
    onLog?.call(tag, message, error: error);
  }
}
