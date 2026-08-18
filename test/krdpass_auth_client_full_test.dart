import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KrdpassAuth client;
  const config = KrdpassConfig(
    redirectUri: 'https://app.example.com/callback',
    clientId: 'test-client',
    environment: KrdpassEnvironment.development,
  );

  const channel = MethodChannel('krd.pass.krdpass_auth');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.add(call);
          if (call.method == 'launchKRDPassForResult') {
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    client.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('KrdpassAuth authenticate (Platform Channel)', () {
    test('calls authenticate and returns success on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(
        requestUri: 'test_request_uri',
        state: 'state_abc',
      );

      await Future.delayed(Duration.zero);
      expect(log.map((c) => c.method).toList(), [
        'configure',
        'launchKRDPassForResult',
      ]);
      expect(log.last.arguments['requestUri'], 'test_request_uri');

      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('onAuthResult', {
            'code': 'auth_code_123',
            'state': 'state_abc',
          }),
        ),
        (data) {},
      );

      final result = await authFuture;
      expect(result.isSuccess, isTrue);
      expect(result.code, 'auth_code_123');
      expect(result.state, 'state_abc');

      debugDefaultTargetPlatformOverride = null;
    });

    test('rejects a callback whose state does not match (CSRF)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(
        requestUri: 'test_request_uri',
        state: 'state_abc',
      );
      await Future.delayed(Duration.zero);

      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('onAuthResult', {
            'code': 'auth_code_123',
            'state': 'forged_state',
          }),
        ),
        (data) {},
      );

      final result = await authFuture;
      expect(result.isStateMismatch, isTrue);
      expect(result.isSuccess, isFalse);

      debugDefaultTargetPlatformOverride = null;
    });

    test('rejects a callback that carries a code but no state', () async {
      // An absent state must fail closed exactly like a mismatch.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(
        requestUri: 'test_request_uri',
        state: 'state_abc',
      );
      await Future.delayed(Duration.zero);

      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('onAuthResult', {'code': 'auth_code_123'}),
        ),
        (data) {},
      );

      final result = await authFuture;
      expect(result.isStateMismatch, isTrue);
      expect(result.isSuccess, isFalse);

      debugDefaultTargetPlatformOverride = null;
    });

    test('calls authenticate and handles error on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(
        requestUri: 'test_request_uri',
        state: 'state_abc',
      );

      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      await binaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('onAuthResult', {
            'error': 'access_denied',
            'error_description': 'User denied access',
          }),
        ),
        (data) {},
      );

      final result = await authFuture;
      expect(result.isSuccess, isFalse);
      expect(result.isCancelled, isTrue);
      // The provider's own reason survives on errorDescription, the one
      // diagnostic a cancelled flow has.
      expect(result.errorMessage, 'User denied access');

      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'maps a provider_not_installed result pushed via onAuthResult',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        client = KrdpassAuth.instance;
        await client.initialize(config: config);

        final authFuture = client.authenticate(
          requestUri: 'uri',
          state: 'state_abc',
        );
        await Future.delayed(Duration.zero);

        const codec = StandardMethodCodec();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              codec.encodeMethodCall(
                const MethodCall('onAuthResult', {
                  'error': 'provider_not_installed',
                }),
              ),
              (_) {},
            );

        final result = await authFuture;
        expect(result.isSuccess, isFalse);
        expect(result.error, 'provider_not_installed');
        expect(result.isProviderNotInstalled, isTrue);
        // installUrl comes from local config, not the channel.
        expect(result.installUrl, config.environment.installUrl);

        debugDefaultTargetPlatformOverride = null;
      },
    );

    test(
      'sends timeoutMillis over the channel, including a value over 5 minutes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        client = KrdpassAuth.instance;
        await client.initialize(config: config);

        const customTimeout = Duration(minutes: 10);
        final authFuture = client.authenticate(
          requestUri: 'test_request_uri',
          state: 'state_abc',
          timeout: customTimeout,
        );
        await Future.delayed(Duration.zero);

        expect(
          log.last.arguments['timeoutMillis'],
          customTimeout.inMilliseconds,
        );

        // Settle the pending flow so the test doesn't leak a hanging future.
        final binaryMessenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const codec = StandardMethodCodec();
        await binaryMessenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('onAuthResult', {
              'code': 'auth_code_123',
              'state': 'state_abc',
            }),
          ),
          (data) {},
        );
        await authFuture;

        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('KrdpassAuth signIn (Client Only)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('successful flow (Delegated to Native)', () async {
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'configure') return true;
            if (call.method == 'signIn') {
              final binaryMessenger = TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger;
              const codec = StandardMethodCodec();

              // The bridge acks first and pushes the outcome afterwards.
              Future.delayed(Duration.zero, () async {
                await binaryMessenger.handlePlatformMessage(
                  channel.name,
                  codec.encodeMethodCall(
                    const MethodCall('onSignInResult', {
                      'accessToken': 'access_token_123',
                      'idToken': 'id_token_123',
                      'tokenType': 'Bearer',
                      'expiresIn': 3600,
                    }),
                  ),
                  (data) {},
                );
              });
              return null;
            }
            return null;
          });

      final tokenResult = await client.signIn(
        timeout: const Duration(seconds: 5),
      );

      expect(tokenResult.accessToken, 'access_token_123');
      expect(tokenResult.idToken, 'id_token_123');
    });

    test('fails if bridge returns error', () async {
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'signIn') {
              final binaryMessenger = TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger;
              const codec = StandardMethodCodec();

              Future.delayed(Duration.zero, () async {
                await binaryMessenger.handlePlatformMessage(
                  channel.name,
                  codec.encodeMethodCall(
                    const MethodCall('onSignInResult', {
                      'error': 'auth_failed',
                      'error_description': 'User cancelled',
                    }),
                  ),
                  (data) {},
                );
              });
              return null;
            }
            return true;
          });

      await expectLater(
        client.signIn(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('auth_failed'),
          ),
        ),
      );
    });

    test(
      'sends timeoutMillis over the channel, including a value over 5 minutes',
      () async {
        client = KrdpassAuth.instance;
        await client.initialize(config: config);

        const customTimeout = Duration(minutes: 10);
        final capturedArgs = <String, dynamic>{};

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'configure') return true;
              if (call.method == 'signIn') {
                capturedArgs.addAll(
                  Map<String, dynamic>.from(call.arguments as Map),
                );
                final binaryMessenger = TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger;
                const codec = StandardMethodCodec();

                Future.delayed(Duration.zero, () async {
                  await binaryMessenger.handlePlatformMessage(
                    channel.name,
                    codec.encodeMethodCall(
                      const MethodCall('onSignInResult', {
                        'accessToken': 'access_token_123',
                        'idToken': 'id_token_123',
                        'tokenType': 'Bearer',
                        'expiresIn': 3600,
                      }),
                    ),
                    (data) {},
                  );
                });
                return null;
              }
              return null;
            });

        final tokenResult = await client.signIn(timeout: customTimeout);

        expect(capturedArgs['timeoutMillis'], customTimeout.inMilliseconds);
        expect(tokenResult.accessToken, 'access_token_123');
      },
    );
  });

  test('an error redirect with the wrong state is rejected', () async {
    // An injected error response carrying someone else's state must fail closed too.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final authFuture = client.authenticate(
      requestUri: 'uri',
      state: 'state_abc',
    );
    await Future.delayed(Duration.zero);

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('onAuthResult', {
              'error': 'invalid_request',
              'error_description': 'injected',
              'state': 'attacker_state',
            }),
          ),
          (_) {},
        );

    expect((await authFuture).isStateMismatch, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a cancelled-code redirect with the wrong state is rejected', () async {
    // access_denied maps to AuthResult.cancelled; its state must still be
    // validated so an injected cancellation cannot carry a foreign state.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final authFuture = client.authenticate(
      requestUri: 'uri',
      state: 'state_abc',
    );
    await Future.delayed(Duration.zero);

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('onAuthResult', {
              'error': 'access_denied',
              'error_description': 'injected',
              'state': 'attacker_state',
            }),
          ),
          (_) {},
        );

    expect((await authFuture).isStateMismatch, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'a malformed signIn payload does not cancel the granted tokens',
    () async {
      // The exchange already succeeded, so a parse failure must not send
      // cancelAuthentication: that would orphan live credentials.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final signInFuture = client.signIn();
      final expectation = expectLater(signInFuture, throwsFormatException);
      await Future.delayed(Duration.zero);

      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            // No expiresIn: KrdpassTokenResult.fromJson rejects it.
            codec.encodeMethodCall(
              const MethodCall('onSignInResult', {'accessToken': 'live_token'}),
            ),
            (_) {},
          );

      await expectation;
      expect(log.map((c) => c.method), isNot(contains('cancelAuthentication')));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('cancelPendingAuthentication unblocks a pending signIn', () async {
    // The Android core drops a cancel issued during the PAR window; without the
    // Dart-side backstop the caller would wait out the full timeout.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final signInFuture = client.signIn();
    final expectation = expectLater(
      signInFuture,
      throwsA(isA<KrdpassCancelledException>()),
    );
    await Future.delayed(Duration.zero); // let signIn reach the channel

    await client.cancelPendingAuthentication();
    await expectation;

    debugDefaultTargetPlatformOverride = null;
  });

  test('re-initializing does not orphan an in-flight flow', () async {
    // initialize() replaces the shared channel handler; a pending flow on the
    // old bridge would otherwise hang until its timeout.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final authFuture = client.authenticate(
      requestUri: 'uri',
      state: 'state_abc',
    );
    await client.initialize(config: config);

    expect((await authFuture).isCancelled, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });

  test('a whitespace-only state is rejected without launching', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final result = await client.authenticate(requestUri: 'uri', state: '   ');
    expect(result.error, 'invalid_request');
    expect(log.any((c) => c.method == 'launchKRDPassForResult'), isFalse);

    debugDefaultTargetPlatformOverride = null;
  });

  test('dispose cleans up resources', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    final authFuture = client.authenticate(
      requestUri: 'uri',
      state: 'state_abc',
    );
    await Future.delayed(Duration.zero);
    client.dispose();

    final result = await authFuture;
    expect(result.isCancelled, isTrue);
    expect(log.map((c) => c.method), contains('cancelAuthentication'));

    debugDefaultTargetPlatformOverride = null;
  });
}
