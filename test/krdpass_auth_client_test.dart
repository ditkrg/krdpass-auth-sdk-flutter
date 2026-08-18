import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassAuth', () {
    test('generatePkcePair returns valid PKCE', () {
      final pkce = KrdpassAuth.instance.generatePkcePair();

      expect(pkce.codeVerifier, isNotEmpty);
      expect(pkce.codeChallenge, isNotEmpty);
      expect(pkce.method, equals('S256'));
      expect(pkce.codeVerifier.length, greaterThanOrEqualTo(43));
      expect(pkce.codeVerifier.length, lessThanOrEqualTo(128));
    });

    // These lock the endpoint constants, which must stay byte-identical with
    // KrdpassEnvironment.kt and KrdpassEnvironment.swift. The Flutter SDK has no
    // buildAuthorizationUrl of its own; the native cores build the URL.
    test('production endpoints match the native cores', () {
      const config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        clientId: 'test-client-id',
      );
      expect(
        config.environment.authUrl,
        equals('https://app.pass.krd/connect/authorize'),
      );
      expect(
        config.environment.authServerUrl,
        equals('https://account.id.krd'),
      );
    });

    test('development endpoints match the native cores', () {
      const config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        clientId: 'test-client-id',
        environment: KrdpassEnvironment.development,
      );
      expect(
        config.environment.authUrl,
        equals('https://app.krdpass.dev.krd/connect/authorize'),
      );
      expect(config.environment.authServerUrl, equals('https://auth.dev.krd'));
    });

    test('production is the default environment', () {
      const config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        clientId: 'test-client-id',
      );
      expect(config.environment, equals(KrdpassEnvironment.production));
    });
  });
}
