typedef LogFunction =
    void Function(
      String level,
      String message, [
      Object? error,
      StackTrace? stackTrace,
    ]);

class KrdpassLogger {
  /// Custom log hook. Null by default: the SDK logs nothing unless the app
  /// provides a function, for production safety.
  static LogFunction? logFunction;

  static void fine(String message) {
    logFunction?.call('FINE', message);
  }

  static void info(String message) {
    logFunction?.call('INFO', message);
  }

  static void warning(String message) {
    logFunction?.call('WARNING', message);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    logFunction?.call('ERROR', message, error, stackTrace);
  }
}
