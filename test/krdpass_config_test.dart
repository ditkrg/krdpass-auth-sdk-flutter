import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassConfig', () {
    group('redirectScheme', () {
      test('returns scheme from custom URL scheme', () {
        const config = KrdpassConfig(
          redirectUri: 'myapp://auth/callback',
          clientId: 'test-client-id',
        );
        expect(config.redirectScheme, equals('myapp'));
      });

      test('returns scheme from https URL', () {
        const config = KrdpassConfig(
          redirectUri: 'https://example.com/auth/callback',
          clientId: 'test-client-id',
        );
        expect(config.redirectScheme, equals('https'));
      });

      test('returns empty string for invalid URI', () {
        const config = KrdpassConfig(
          redirectUri: ':::invalid:::',
          clientId: 'test-client-id',
        );
        expect(config.redirectScheme, equals(''));
      });
    });

    group('redirectHost', () {
      test('returns host from custom URL scheme', () {
        const config = KrdpassConfig(
          redirectUri: 'myapp://auth/callback',
          clientId: 'test-client-id',
        );
        expect(config.redirectHost, equals('auth'));
      });

      test('returns host from https URL', () {
        const config = KrdpassConfig(
          redirectUri: 'https://example.com/auth/callback',
          clientId: 'test-client-id',
        );
        expect(config.redirectHost, equals('example.com'));
      });
    });

    group('isValidRedirectUri', () {
      test('rejects custom schemes (HTTPS-only enforcement)', () {
        const config = KrdpassConfig(
          redirectUri: 'myapp://auth/callback',
          clientId: 'test-client-id',
        );

        expect(
          config.isValidRedirectUri(Uri.parse('myapp://auth/callback')),
          isFalse, // Custom schemes are rejected
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('https://example.com/auth/callback'),
          ),
          isFalse, // Wrong host even with HTTPS
        );
      });

      test('validates https scheme and host matches (path not required)', () {
        const config = KrdpassConfig(
          redirectUri: 'https://example.com/auth/callback',
          clientId: 'test-client-id',
        );

        expect(
          config.isValidRedirectUri(
            Uri.parse('https://example.com/auth/callback'),
          ),
          isTrue,
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('https://example.com/different/path'),
          ),
          isTrue,
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('https://different.com/auth/callback'),
          ),
          isFalse,
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('https://example.com:8443/auth/callback'),
          ),
          isFalse,
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('http://example.com/auth/callback'),
          ),
          isFalse,
        );
      });

      test('returns false for invalid config URI', () {
        const config = KrdpassConfig(
          redirectUri: ':::invalid:::',
          clientId: 'test-client-id',
        );
        expect(
          config.isValidRedirectUri(Uri.parse('myapp://callback')),
          isFalse,
        );
      });

      test('handles query parameters in incoming URI', () {
        const config = KrdpassConfig(
          redirectUri: 'https://myapp.example.com/callback',
          clientId: 'test-client-id',
        );

        expect(
          config.isValidRedirectUri(
            Uri.parse('https://myapp.example.com/callback?code=abc&state=xyz'),
          ),
          isTrue,
        );
      });

      test('handles universal link with path', () {
        const config = KrdpassConfig(
          redirectUri: 'https://app.example.com/oauth/callback',
          clientId: 'test-client-id',
        );

        expect(
          config.isValidRedirectUri(
            Uri.parse('https://app.example.com/oauth/callback?code=abc'),
          ),
          isTrue,
        );
        expect(
          config.isValidRedirectUri(
            Uri.parse('https://api.example.com/oauth/callback'),
          ),
          isFalse,
        );
      });
    });

    group('stateValidator', () {
      test('is optional and can be null', () {
        const config = KrdpassConfig(
          redirectUri: 'myapp://callback',
          clientId: 'test-client-id',
        );
        expect(config.stateValidator, isNull);
      });

      test('can be provided for custom state validation', () {
        final validStates = <String>{'state1', 'state2'};
        final config = KrdpassConfig(
          redirectUri: 'myapp://callback',
          stateValidator: validStates.contains,
          clientId: 'test-client-id',
        );

        expect(config.stateValidator!('state1'), isTrue);
        expect(config.stateValidator!('state2'), isTrue);
        expect(config.stateValidator!('invalid'), isFalse);
        expect(config.stateValidator!(null), isFalse);
      });
    });
  });
}
