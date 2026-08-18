import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

/// Locks that a failed signIn() surfaces a typed exception derived from the
/// native error code, driven through the real platform-channel path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KrdpassAuth client;
  const config = KrdpassConfig(
    redirectUri: 'https://app.example.com/callback',
    clientId: 'test-client',
    environment: KrdpassEnvironment.development,
  );
  const channel = MethodChannel('krd.pass.krdpass_auth');
  const codec = StandardMethodCodec();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    client.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> emitSignInError(String code) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        MethodCall('onSignInResult', <String, dynamic>{
          'error': code,
          'error_description': 'native: $code',
        }),
      ),
      (_) {},
    );
  }

  /// native error code -> expected typed exception matcher
  final cases = <String, Matcher>{
    'cancelled': isA<KrdpassCancelledException>(),
    'user_cancelled': isA<KrdpassCancelledException>(),
    'access_denied': isA<KrdpassCancelledException>(),
    'login_required': isA<KrdpassCancelledException>(),
    'consent_denied': isA<KrdpassCancelledException>(),
    'timeout': isA<KrdpassTimeoutException>(),
    'busy': isA<KrdpassBusyException>(),
    // network_error keeps the canonical fallback (raw detail stays in cause);
    // authentication_failed surfaces the native text verbatim.
    'network_error': isA<KrdpassNetworkException>().having(
      (e) => e.message,
      'message',
      'Sign in failed',
    ),
    'authentication_failed': isA<KrdpassAuthenticationException>().having(
      (e) => e.message,
      'message',
      'native: authentication_failed',
    ),
    // RFC 9207 mix-up: keeps its own code, and the canonical message replaces
    // the bridge text so it cannot be confused with a CSRF state_mismatch.
    'issuer_mismatch': isA<KrdpassAuthenticationException>()
        .having((e) => e.code, 'code', 'issuer_mismatch')
        .having(
          (e) => e.message,
          'message',
          'Issuer mismatch: the response did not come from the expected authorization server',
        ),
    // Token replay indicator: same treatment as issuer_mismatch.
    'nonce_mismatch': isA<KrdpassAuthenticationException>()
        .having((e) => e.code, 'code', 'nonce_mismatch')
        .having(
          (e) => e.message,
          'message',
          'ID token nonce mismatch (possible token replay)',
        ),
  };

  for (final entry in cases.entries) {
    final code = entry.key;
    final matcher = entry.value;
    test('signIn maps native "$code" to the typed exception', () async {
      await (client = KrdpassAuth.instance).initialize(config: config);

      final future = client.signIn(scopes: const ['openid']);
      final expectation = expectLater(future, throwsA(matcher));

      await Future<void>.delayed(
        Duration.zero,
      ); // let signIn invoke the channel
      await emitSignInError(code);
      await expectation;
    });
  }

  test(
    'an unknown native code preserves the code on KrdpassAuthenticationException',
    () async {
      await (client = KrdpassAuth.instance).initialize(config: config);

      final future = client.signIn(scopes: const ['openid']);
      final expectation = expectLater(
        future,
        throwsA(
          isA<KrdpassAuthenticationException>().having(
            (e) => e.code,
            'code',
            'provider_not_installed',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await emitSignInError('provider_not_installed');
      await expectation;
    },
  );

  // invalid_id_token is deliberately not mapped: the native text is the only
  // diagnostic and a canonical string would misreport it.
  test(
    'invalid_id_token keeps the native message instead of a canonical one',
    () async {
      await (client = KrdpassAuth.instance).initialize(config: config);

      final future = client.signIn(scopes: const ['openid']);
      final expectation = expectLater(
        future,
        throwsA(
          isA<KrdpassAuthenticationException>()
              .having((e) => e.code, 'code', 'invalid_id_token')
              .having((e) => e.message, 'message', 'native: invalid_id_token')
              .having(
                (e) => e.message,
                'message',
                isNot('Token response did not include an id_token'),
              ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await emitSignInError('invalid_id_token');
      await expectation;
    },
  );
}
