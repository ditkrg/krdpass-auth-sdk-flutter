import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';
// kCancelledCodes is not exported, so this test reaches it by its src/ path.
import 'package:krdpass_auth_flutter/src/models/auth_result.dart'
    show kCancelledCodes;

void main() {
  group('AuthResult', () {
    test('isSuccess returns true when code is present and no error', () {
      const result = AuthResult.success(code: 'abc123', state: 'state123');
      expect(result.isSuccess, isTrue);
      expect(result.isError, isFalse);
      expect(result.isCancelled, isFalse);
    });

    test('isError returns true when error is present', () {
      const result = AuthResult.error(
        error: 'authorization_error',
        errorDescription: 'Something went wrong',
      );
      expect(result.isError, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('isCancelled returns true for cancelled result', () {
      const result = AuthResult.cancelled();
      expect(result.isCancelled, isTrue);
    });

    test('isTimeout returns true for timeout error', () {
      const result = AuthResult.timeout();
      expect(result.isTimeout, isTrue);
    });

    test('errorMessage returns errorDescription when available', () {
      const result = AuthResult.error(
        error: 'some_error',
        errorDescription: 'Human readable message',
      );
      expect(result.errorMessage, equals('Human readable message'));
    });

    test('errorMessage returns error code when no description', () {
      const result = AuthResult.error(error: 'some_error');
      expect(result.errorMessage, equals('some_error'));
    });

    test('toString formats success correctly', () {
      const result = AuthResult.success(code: 'abcdefghij', state: 'state123');
      expect(result.toString(), contains('success'));
      expect(result.toString(), contains('[REDACTED]'));
    });

    test('toString formats error correctly', () {
      const result = AuthResult.error(
        error: 'some_error',
        errorDescription: 'Description',
      );
      expect(result.toString(), contains('some_error'));
    });

    test('equality works correctly', () {
      const result1 = AuthResult.success(code: 'abc', state: 'xyz');
      const result2 = AuthResult.success(code: 'abc', state: 'xyz');
      const result3 = AuthResult.success(code: 'abc', state: 'different');

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('hashCode is consistent', () {
      const result1 = AuthResult.success(code: 'abc', state: 'xyz');
      const result2 = AuthResult.success(code: 'abc', state: 'xyz');

      expect(result1.hashCode, equals(result2.hashCode));
    });

    test('handles null values correctly', () {
      const result = AuthResult.error(error: 'test');
      expect(result.code, isNull);
      expect(result.state, isNull);
      expect(result.error, equals('test'));
      expect(result.errorDescription, isNull);
      expect(result.errorMessage, equals('test'));
    });

    test('every cancellation code is observable as isCancelled', () {
      // A code removed from the set fails here instead of silently turning a
      // cancellation into a generic error.
      for (final code in kCancelledCodes) {
        expect(
          AuthResult.error(error: code).isCancelled,
          isTrue,
          reason: '$code must classify as a cancellation',
        );
      }
    });
  });

  test('kCancelledCodes is not part of the public API', () {
    // Exporting it would freeze an implementation detail as public surface.
    final library = File('lib/krdpass_auth_flutter.dart').readAsStringSync();

    expect(
      library,
      contains("export 'src/models/auth_result.dart' hide kCancelledCodes;"),
    );
  });
}
