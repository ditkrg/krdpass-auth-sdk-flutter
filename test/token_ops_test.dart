import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

/// Covers refreshTokens, revokeToken and getUserInfo, in particular that the
/// native error codes map to the documented exception types.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KrdpassAuth client;
  const config = KrdpassConfig(
    redirectUri: 'https://app.example.com/callback',
    clientId: 'test-client',
    environment: KrdpassEnvironment.development,
  );
  const channel = MethodChannel('krd.pass.krdpass_auth');

  /// Installs a handler that answers [method] with [reply], or throws [error].
  void mockChannel(String method, {Object? reply, PlatformException? error}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != method) return true;
          if (error != null) throw error;
          return reply;
        });
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    client = KrdpassAuth.instance;
    await client.initialize(config: config);
  });

  tearDown(() {
    client.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('configure reaches the native side', () {
    // Both bridges answer invalid_request until configure has run. Asserting the
    // ORDERED call sequence is the point: it catches a missing or duplicated configure.
    late List<String> methods;

    setUp(() {
      methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'refreshTokens') {
              return const {
                'accessToken': 'access_123',
                'tokenType': 'Bearer',
                'expiresIn': 3600,
              };
            }
            if (call.method == 'getUserInfo') return const {'sub': 'user-1'};
            if (call.method == 'verifyToken') return const {'sub': 'user-1'};
            return true;
          });
    });

    test('a cold-start refreshTokens configures first', () async {
      await client.refreshTokens(refreshToken: 'stored_refresh');

      expect(methods, ['configure', 'refreshTokens']);
    });

    test('configure is sent once per initialize, not once per call', () async {
      // iOS allocates a fresh native KrdpassAuth per configure and Android clears
      // the JWKS cache, so re-sending it would drop native state mid-session.
      await client.refreshTokens(refreshToken: 'stored_refresh');
      await client.revokeToken(token: 'stored_refresh');
      await client.getUserInfo(accessToken: 'access_123');
      await client.verifyToken(idToken: 'id_token');

      expect(methods, [
        'configure',
        'refreshTokens',
        'revokeToken',
        'getUserInfo',
        'verifyToken',
      ]);
    });

    test('the signIn happy path still configures exactly once', () async {
      final signInFuture = client.signIn(scopes: const ['openid']);
      await Future<void>.delayed(Duration.zero);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onSignInResult', <String, dynamic>{
                'accessToken': 'access_123',
                'tokenType': 'Bearer',
                'expiresIn': 3600,
                'refreshToken': 'refresh_456',
              }),
            ),
            (_) {},
          );
      final tokens = await signInFuture;
      expect(tokens.accessToken, 'access_123');

      await client.refreshTokens(refreshToken: tokens.refreshToken!);
      await client.revokeToken(token: 'refresh_456');

      expect(methods, ['configure', 'signIn', 'refreshTokens', 'revokeToken']);
    });

    test('a failed configure is retried on the next call', () async {
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'configure' && attempts++ == 0) {
              throw PlatformException(
                code: 'invalid_request',
                message: 'clientId is required',
              );
            }
            if (call.method == 'refreshTokens') {
              return const {
                'accessToken': 'access_123',
                'tokenType': 'Bearer',
                'expiresIn': 3600,
              };
            }
            return true;
          });

      await expectLater(
        client.refreshTokens(refreshToken: 'stored_refresh'),
        throwsA(isA<KrdpassException>()),
      );
      await client.refreshTokens(refreshToken: 'stored_refresh');

      expect(methods, ['configure', 'configure', 'refreshTokens']);
    });

    test('a configure failure keeps its native code and message', () async {
      // Wrapping them would leave an integration bug indistinguishable from a
      // runtime auth failure.
      mockChannel(
        'configure',
        error: PlatformException(
          code: 'invalid_request',
          message: 'SDK not configured. Call configure first.',
        ),
      );

      await expectLater(
        client.refreshTokens(refreshToken: 'stored_refresh'),
        throwsA(
          isA<KrdpassAuthenticationException>()
              .having((e) => e.code, 'code', 'invalid_request')
              .having(
                (e) => e.message,
                'message',
                'SDK not configured. Call configure first.',
              ),
        ),
      );
    });
  });

  group('refreshTokens', () {
    test('parses the native token map', () async {
      mockChannel(
        'refreshTokens',
        reply: {
          'accessToken': 'access_123',
          'tokenType': 'Bearer',
          'expiresIn': 3600,
          'refreshToken': 'refresh_456',
        },
      );

      final tokens = await client.refreshTokens(refreshToken: 'old_refresh');

      expect(tokens.accessToken, 'access_123');
      expect(tokens.refreshToken, 'refresh_456');
      expect(tokens.expiresIn, 3600);
    });

    test('a malformed payload is a FormatException, as in signIn', () async {
      mockChannel('refreshTokens', reply: const {'tokenType': 'Bearer'});

      await expectLater(
        client.refreshTokens(refreshToken: 'old_refresh'),
        throwsFormatException,
      );
    });
  });

  group('revokeToken', () {
    test('forwards the token and the type hint', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });

      await client.revokeToken(
        token: 'refresh_456',
        tokenTypeHint: 'refresh_token',
      );

      final revoke = calls.singleWhere((c) => c.method == 'revokeToken');
      expect(revoke.arguments['token'], 'refresh_456');
      expect(revoke.arguments['tokenTypeHint'], 'refresh_token');
    });
  });

  group('getUserInfo', () {
    test('rejects an empty access token before touching the channel', () {
      expect(
        () => client.getUserInfo(accessToken: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('parses the camelCase bridge map', () async {
      mockChannel(
        'getUserInfo',
        reply: {
          'sub': 'user-1',
          'givenName': 'Ali',
          'familyName': 'Karim',
          'citizenFirst': 'Ali',
          'citizenSurname': 'Karim',
        },
      );

      final info = await client.getUserInfo(accessToken: 'access_123');

      expect(info.sub, 'user-1');
      expect(info.givenName, 'Ali');
      expect(info.citizenFullName, 'Ali Karim');
    });

    test('a response with no sub is a FormatException, as in signIn', () async {
      mockChannel('getUserInfo', reply: const {'name': 'Ali'});

      await expectLater(
        client.getUserInfo(accessToken: 'access_123'),
        throwsFormatException,
      );
    });
  });

  group('error taxonomy on the token operations', () {
    // Each native code must reach its own exception type, or README's advice to
    // catch KrdpassNetworkException here could never fire.
    final cases = <String, Matcher>{
      'network_error': isA<KrdpassNetworkException>(),
      'timeout': isA<KrdpassTimeoutException>(),
      'busy': isA<KrdpassBusyException>(),
      'cancelled': isA<KrdpassCancelledException>(),
      'refresh_failed': isA<KrdpassAuthenticationException>(),
    };

    for (final entry in cases.entries) {
      test('refreshTokens maps "${entry.key}"', () async {
        mockChannel('refreshTokens', error: PlatformException(code: entry.key));
        await expectLater(
          client.refreshTokens(refreshToken: 'old_refresh'),
          throwsA(entry.value),
        );
      });
    }

    test('revokeToken maps "network_error"', () async {
      mockChannel(
        'revokeToken',
        error: PlatformException(code: 'network_error'),
      );
      await expectLater(
        client.revokeToken(token: 'refresh_456'),
        throwsA(isA<KrdpassNetworkException>()),
      );
    });

    test('getUserInfo maps "network_error"', () async {
      mockChannel(
        'getUserInfo',
        error: PlatformException(code: 'network_error'),
      );
      await expectLater(
        client.getUserInfo(accessToken: 'access_123'),
        throwsA(isA<KrdpassNetworkException>()),
      );
    });

    test('the raw native detail stays out of the displayed message', () async {
      // message is what apps render; a raw CAS body or OS error string is not user-safe.
      mockChannel(
        'refreshTokens',
        error: PlatformException(
          code: 'network_error',
          details: 'Unable to resolve host "auth.dev.krd"',
        ),
      );

      await expectLater(
        client.refreshTokens(refreshToken: 'old_refresh'),
        throwsA(
          isA<KrdpassNetworkException>()
              .having((e) => e.message, 'message', 'Failed to refresh tokens')
              .having((e) => e.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });
  });
}
