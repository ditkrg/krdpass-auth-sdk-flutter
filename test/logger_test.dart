import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassLogger', () {
    late List<String> loggedMessages;

    setUp(() {
      loggedMessages = [];
      KrdpassLogger.logFunction = (level, message, [error, stackTrace]) {
        loggedMessages.add('$level: $message');
        if (error != null) {
          loggedMessages.add('Error: $error');
        }
      };
    });

    tearDown(() {
      KrdpassLogger.logFunction = null; // Reset to no logging
    });

    test('logs fine level messages', () {
      KrdpassLogger.fine('Debug message');
      expect(loggedMessages, contains('FINE: Debug message'));
    });

    test('logs info level messages', () {
      KrdpassLogger.info('Info message');
      expect(loggedMessages, contains('INFO: Info message'));
    });

    test('logs warning level messages', () {
      KrdpassLogger.warning('Warning message');
      expect(loggedMessages, contains('WARNING: Warning message'));
    });

    test('logs error messages with exception', () {
      final exception = Exception('Test error');
      KrdpassLogger.error('Error message', exception);
      expect(loggedMessages, contains('ERROR: Error message'));
      expect(loggedMessages, contains('Error: Exception: Test error'));
    });

    test('does not log when logFunction is null', () {
      KrdpassLogger.logFunction = null;
      KrdpassLogger.info('This should not be logged');
      expect(loggedMessages, isEmpty);
    });

    test('can be configured to use app logger', () {
      final appLogs = <String>[];
      KrdpassLogger.logFunction = (level, message, [error, stackTrace]) {
        appLogs.add('APP-$level: $message');
      };

      KrdpassLogger.warning('Test warning');
      expect(appLogs, contains('APP-WARNING: Test warning'));
    });
  });
}
