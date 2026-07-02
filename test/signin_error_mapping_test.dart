import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

/// Locks the headline DX guarantee: a failed client-only signIn() surfaces a
/// *typed* exception derived from the native error code, not a generic failure.
/// Drives the real platform-channel path (onSignInResult) so a regression in the
/// shim -> PlatformException -> _mapPlatformError chain is caught.
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
    // network_error keeps the canonical fallback (native network detail may be raw, so it stays
    // in `cause`). authentication_failed surfaces the native SDK's CANONICAL signIn-flow message
    // verbatim, since the native side is the source of truth for those (parity with Android/iOS/RN).
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
}
