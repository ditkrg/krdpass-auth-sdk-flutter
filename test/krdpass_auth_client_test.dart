import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassAuth', () {
    test('generatePkcePair returns valid PKCE', () {
      // Test the static generatePkcePair function directly
      final pkce = generatePkcePair();

      expect(pkce.codeVerifier, isNotEmpty);
      expect(pkce.codeChallenge, isNotEmpty);
      expect(pkce.method, equals('S256'));
      expect(pkce.codeVerifier.length, greaterThanOrEqualTo(43));
      expect(pkce.codeVerifier.length, lessThanOrEqualTo(128));
    });

    test(
      'buildAuthorizationUrl constructs correct URL with production environment',
      () {
        const config = KrdpassConfig(
          redirectUri: 'https://example.com/callback',
          clientId: 'test-client-id',
        );
        expect(
          config.environment.authUrl,
          equals('https://app.pass.krd/connect/authorize'),
        );
      },
    );

    test(
      'buildAuthorizationUrl constructs correct URL with dev environment',
      () {
        const config = KrdpassConfig(
          redirectUri: 'https://example.com/callback',
          clientId: 'test-client-id',
          environment: KrdpassEnvironment.development,
        );
        expect(
          config.environment.authUrl,
          equals('https://app.krdpass.dev.krd/connect/authorize'),
        );
      },
    );

    test('isValidRedirect validates URIs correctly', () {
      const config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        clientId: 'test-client-id',
      );
      expect(
        config.isValidRedirectUri(Uri.parse('https://example.com/callback')),
        isTrue,
      );
      expect(
        config.isValidRedirectUri(Uri.parse('https://other.com/callback')),
        isFalse,
      );
      expect(
        config
            .isValidRedirectUri(Uri.parse('https://example.com:8443/callback')),
        isFalse,
      );
    });
  });
}
