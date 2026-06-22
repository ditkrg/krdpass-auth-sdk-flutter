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
      // detailed target platform override
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(requestUri: 'test_request_uri', state: 'state_abc');

      // Simulate success callback from native side
      await Future.delayed(Duration.zero); // wait for channel invoke
      // Constructor calls configure, authenticate calls configure again
      // We expect at least these calls
      expect(log.length, greaterThanOrEqualTo(1));
      expect(log.last.method, 'launchKRDPassForResult');
      expect(log.last.arguments['requestUri'], 'test_request_uri');

      // Simulate result callback
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

    test('calls authenticate and handles error on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      final authFuture = client.authenticate(requestUri: 'test_request_uri', state: 'state_abc');

      // Simulate error callback from native side
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

      debugDefaultTargetPlatformOverride = null;
    });

    test('returns platform error if launch fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launchKRDPassForResult') {
          return false; // Launch failed
        }
        return null;
      });

      client = KrdpassAuth.instance;
      await client.initialize(config: config);
      final result = await client.authenticate(requestUri: 'uri', state: 'state_abc');

      expect(result.isSuccess, isFalse);
      expect(result.error, 'launch_failed');

      debugDefaultTargetPlatformOverride = null;
    });
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
          // Simulate native result
          final binaryMessenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          const codec = StandardMethodCodec();

          // We must send the response back asynchronously
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

      final tokenResult =
          await client.signIn(timeout: const Duration(seconds: 5));

      expect(tokenResult.accessToken, 'access_token_123');
      expect(tokenResult.idToken, 'id_token_123');
    });

    test('fails if bridge returns error', () async {
      client = KrdpassAuth.instance;
      await client.initialize(config: config);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'signIn') {
          final binaryMessenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

      expect(
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
  });

  test('dispose cleans up resources', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    client = KrdpassAuth.instance;
    await client.initialize(config: config);

    // Start auth but don't finish
    final authFuture = client.authenticate(requestUri: 'uri', state: 'state_abc');

    // Dispose should cancel pending auth
    client.dispose();

    final result = await authFuture;
    expect(result.isCancelled, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });
}
