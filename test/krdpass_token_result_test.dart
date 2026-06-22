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
  });
}
