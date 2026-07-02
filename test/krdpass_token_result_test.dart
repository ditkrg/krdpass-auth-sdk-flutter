import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassTokenResult', () {
    test('can be created with all fields', () {
      const result = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
        refreshToken: 'refresh_123',
        scope: 'openid profile',
      );

      expect(result.accessToken, equals('access_123'));
      expect(result.idToken, equals('id_123'));
      expect(result.tokenType, equals('Bearer'));
      expect(result.expiresIn, equals(3600));
      expect(result.refreshToken, equals('refresh_123'));
      expect(result.scope, equals('openid profile'));
    });

    test('can be created with required fields only', () {
      const result = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
      );

      expect(result.accessToken, equals('access_123'));
      expect(result.tokenType, equals('Bearer'));
      expect(result.expiresIn, equals(3600));
      expect(result.idToken, isNull);
      expect(result.refreshToken, isNull);
      expect(result.scope, isNull);
    });

    test('equality works correctly', () {
      const result1 = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
      );
      const result2 = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
      );
      const result3 = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'different_id',
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('hashCode is consistent', () {
      const result1 = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
      );
      const result2 = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
      );

      expect(result1.hashCode, equals(result2.hashCode));
    });

    test('fromJson handles snake_case keys and a double expiresIn', () {
      final result = KrdpassTokenResult.fromJson({
        'access_token': 'access_123',
        'token_type': 'Bearer',
        'expires_in': 3600.0, // a JSON number can cross the channel as a double
        'refresh_token': 'refresh_123',
      });

      expect(result.accessToken, equals('access_123'));
      expect(result.expiresIn, equals(3600));
      expect(result.refreshToken, equals('refresh_123'));
    });

    test('fromJson applies defaults for a partial map', () {
      final result = KrdpassTokenResult.fromJson(const <String, dynamic>{});

      expect(result.accessToken, equals(''));
      expect(result.tokenType, equals('Bearer'));
      expect(result.expiresIn, equals(3600));
      expect(result.idToken, isNull);
    });

    test('fromJson stamps receivedAt locally (never read from the map)', () {
      final before = DateTime.now();
      final result = KrdpassTokenResult.fromJson({
        'access_token': 'access_123',
        'expires_in': 3600,
        // A backend-echoed receivedAt must be ignored: it's another machine's clock.
        'receivedAt': '1970-01-01T00:00:00Z',
      });
      final after = DateTime.now();

      expect(result.receivedAt, isNotNull);
      expect(result.receivedAt!.isBefore(before), isFalse);
      expect(result.receivedAt!.isAfter(after), isFalse);
    });

    test(
      'isExpired trips once the token is past expiry (parity with the other SDKs)',
      () {
        final result = KrdpassTokenResult.fromJson({
          'access_token': 'access_123',
          'expires_in': 30,
        });

        // A skew wider than the remaining lifetime treats the token as expired...
        expect(result.isExpired(skew: const Duration(seconds: 90)), isTrue);
        // ...while no skew leaves a freshly-issued token valid.
        expect(result.isExpired(skew: Duration.zero), isFalse);
      },
    );
  });
}
