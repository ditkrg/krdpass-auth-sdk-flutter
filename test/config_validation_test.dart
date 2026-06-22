import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassConfig Redirect Validation', () {
    test('accepts exact HTTPS match', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final validUri = Uri.parse('https://myapp.example.com/auth/callback');
      expect(config.isValidRedirectUri(validUri), isTrue);
    });

    test('rejects custom schemes', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final customUri = Uri.parse('myapp://auth/callback');
      expect(config.isValidRedirectUri(customUri), isFalse);
    });

    test('rejects different HTTPS host', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final wrongHostUri = Uri.parse(
        'https://otherapp.example.com/auth/callback',
      );
      expect(config.isValidRedirectUri(wrongHostUri), isFalse);
    });

    test('rejects HTTPS port mismatch', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final portMismatchUri =
          Uri.parse('https://myapp.example.com:8443/auth/callback');
      expect(config.isValidRedirectUri(portMismatchUri), isFalse);
    });

    test('accepts same host different HTTPS path', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final differentPathUri =
          Uri.parse('https://myapp.example.com/auth/other');
      expect(config.isValidRedirectUri(differentPathUri), isTrue);
    });

    test('rejects HTTP instead of HTTPS', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final httpUri = Uri.parse('http://myapp.example.com/auth/callback');
      expect(config.isValidRedirectUri(httpUri), isFalse);
    });

    test('handles query parameters correctly', () {
      const config = KrdpassConfig(
        redirectUri: 'https://myapp.example.com/auth/callback',
        clientId: 'test-client-id',
      );

      final uriWithQuery = Uri.parse(
        'https://myapp.example.com/auth/callback?code=123&state=abc',
      );
      expect(config.isValidRedirectUri(uriWithQuery), isTrue);
    });

    test('rejects if configured URI is invalid', () {
      const config = KrdpassConfig(
        redirectUri: 'not-a-valid-uri',
        clientId: 'test-client-id',
      );

      final validUri = Uri.parse('https://myapp.example.com/auth/callback');
      expect(config.isValidRedirectUri(validUri), isFalse);
    });
  });

  group('KrdpassAuthClient State Validation', () {
    test('state validation logic works', () {
      final config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        stateValidator: (state) => state == 'expected-state',
        clientId: 'test-client-id',
      );

      // Test the validator directly
      expect(config.stateValidator!('expected-state'), isTrue);
      expect(config.stateValidator!('wrong-state'), isFalse);
      expect(config.stateValidator!(null), isFalse);
    });
  });
}
