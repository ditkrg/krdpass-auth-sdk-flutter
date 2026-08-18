import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassTokenResult', () {
    // receivedAt is stamped from the clock when omitted, so equality tests pass
    // it explicitly.
    final stamp = DateTime.utc(2026, 7, 29);

    test('value equality covers every field, including receivedAt', () {
      final base = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
        receivedAt: stamp,
      );
      final same = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
        receivedAt: stamp,
      );
      final differentIdToken = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'different_id',
        receivedAt: stamp,
      );
      final differentStamp = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
        receivedAt: stamp.add(const Duration(seconds: 1)),
      );

      expect(base, equals(same));
      expect(base.hashCode, equals(same.hashCode));
      expect(base, isNot(equals(differentIdToken)));
      expect(base, isNot(equals(differentStamp)));
    });

    test('toString redacts every credential it carries', () {
      final result = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 3600,
        idToken: 'id_123',
        refreshToken: 'refresh_123',
        scope: 'openid profile',
        receivedAt: stamp,
      );

      final text = result.toString();
      expect(text, isNot(contains('access_123')));
      expect(text, isNot(contains('id_123')));
      expect(text, isNot(contains('refresh_123')));
      // Non-sensitive fields stay readable so the value is still debuggable.
      expect(text, contains('Bearer'));
      expect(text, contains('openid profile'));
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

    test('fromJson rejects a response with no usable access token', () {
      // A truncated bridge payload must not parse as a success.
      expect(
        () => KrdpassTokenResult.fromJson(const <String, dynamic>{}),
        throwsFormatException,
      );
      expect(
        () => KrdpassTokenResult.fromJson(const {
          'access_token': '',
          'expires_in': 3600,
        }),
        throwsFormatException,
      );
    });

    test('fromJson rejects a response with no expires_in', () {
      expect(
        () => KrdpassTokenResult.fromJson(const {'access_token': 'access_123'}),
        throwsFormatException,
      );
    });

    test('fromJson still defaults only the optional fields', () {
      final result = KrdpassTokenResult.fromJson(const {
        'access_token': 'access_123',
        'expires_in': 3600,
      });

      expect(result.tokenType, equals('Bearer'));
      expect(result.idToken, isNull);
      expect(result.refreshToken, isNull);
      expect(result.scope, isNull);
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

      expect(result.receivedAt.isBefore(before), isFalse);
      expect(result.receivedAt.isAfter(after), isFalse);
    });

    test('a hand-constructed result still expires', () {
      final result = KrdpassTokenResult(
        accessToken: 'access_123',
        tokenType: 'Bearer',
        expiresIn: 30,
        receivedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(result.isExpired(skew: Duration.zero), isTrue);
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

    test(
      'the exact expiry instant counts as expired, matching Android and iOS',
      () {
        final result = KrdpassTokenResult(
          accessToken: 'access_123',
          tokenType: 'Bearer',
          expiresIn: 60,
          receivedAt: DateTime.now().subtract(const Duration(seconds: 60)),
        );

        expect(result.isExpired(skew: Duration.zero), isTrue);
      },
    );
  });
}
