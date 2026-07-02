/// Log function signature for custom logging
typedef LogFunction =
    void Function(
      String level,
      String message, [
      Object? error,
      StackTrace? stackTrace,
    ]);

/// Logger utility for the KRDPASS SDK
class KrdpassLogger {
  /// Configure custom logging for the SDK
  ///
  /// By default, the SDK logs nothing for production safety.
  /// To enable logging, provide a log function:
  ///
  /// ```dart
  /// // Simple console logging
  /// KrdpassLogger.logFunction = (level, message, error, stackTrace) {
  ///   print('KRDPASS $level: $message');
  /// };
  ///
  /// // Or integrate with your app's logger
  /// KrdpassLogger.logFunction = (level, message, error, stackTrace) {
  ///   myLogger.log(level, message, error: error, stackTrace: stackTrace);
  /// };
  ///
  /// // Disable logging (default)
  /// KrdpassLogger.logFunction = null;
  /// ```
  static LogFunction? logFunction;

  /// Log a fine (debug) message
  static void fine(String message) {
    logFunction?.call('FINE', message);
  }

  /// Log an info message
  static void info(String message) {
    logFunction?.call('INFO', message);
  }

  /// Log a warning message
  static void warning(String message) {
    logFunction?.call('WARNING', message);
  }

  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    logFunction?.call('ERROR', message, error, stackTrace);
  }
}
