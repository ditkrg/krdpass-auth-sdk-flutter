import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('krd.pass.krdpass_auth');

  late KrdpassAuth client;
  const config = KrdpassConfig(
    redirectUri: 'https://app.example.com/callback',
    clientId: 'test-client',
    environment: KrdpassEnvironment.development,
  );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'configure') return true;
          if (call.method == 'verifyToken') {
            final token = (call.arguments as Map)['token'] as String;
            if (token == 'invalid-token') {
              throw PlatformException(
                code: 'verification_failed',
                message: 'Invalid signature',
              );
            }
            return {'sub': 'test-user', 'iss': 'https://auth.example.gov'};
          }
          return null;
        });

    client = KrdpassAuth.instance;
    await client.initialize(config: config);
  });

  tearDown(() {
    client.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('verifyToken', () {
    test('throws ArgumentError for empty idToken', () async {
      expect(
        () => client.verifyToken(idToken: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('calls native verifyToken and returns result', () async {
      final claims = await client.verifyToken(idToken: 'valid-token');
      expect(claims['sub'], equals('test-user'));
    });

    test('derives audience and issuer natively, not over the channel', () async {
      final calls = <Map<String, dynamic>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'verifyToken') {
              calls.add(Map<String, dynamic>.from(call.arguments));
              return {'status': 'ok'};
            }
            return true;
          });

      await client.verifyToken(
        idToken: 'token123',
        clockSkew: const Duration(seconds: 30),
      );

      expect(calls.length, 1);
      expect(calls.first['token'], 'token123');
      // Issuer and audience are pinned from the config inside the native cores,
      // so neither crosses the channel.
      expect(calls.first.containsKey('audience'), isFalse);
      expect(calls.first.containsKey('issuer'), isFalse);
      expect(calls.first['clockSkew'], 30);
    });

    test('throws KrdpassTokenValidationException on bridge error', () async {
      await expectLater(
        client.verifyToken(idToken: 'invalid-token'),
        throwsA(isA<KrdpassTokenValidationException>()),
      );
    });

    test(
      'surfaces the native code so a JWKS blip stays distinguishable',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'verifyToken') {
                throw PlatformException(code: 'network_error');
              }
              return true;
            });

        await expectLater(
          client.verifyToken(idToken: 'token123'),
          throwsA(
            isA<KrdpassTokenValidationException>().having(
              (e) => e.code,
              'code',
              'network_error',
            ),
          ),
        );
      },
    );
  });
}
