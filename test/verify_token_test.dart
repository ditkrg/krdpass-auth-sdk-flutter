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
            code: 'VERIFICATION_FAILED',
            message: 'Invalid signature',
          );
        }
        return {'sub': 'test-user', 'iss': 'https://auth.krdpass.com'};
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
    test('throws ArgumentError for empty token', () async {
      expect(
        () => client.verifyToken(token: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('calls native verifyToken and returns result', () async {
      final claims = await client.verifyToken(token: 'valid-token');
      expect(claims['sub'], equals('test-user'));
    });

    test('passes parameters to native bridge', () async {
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
        token: 'token123',
        issuer: 'issuer123',
        audience: 'aud123',
        clockSkew: const Duration(seconds: 30),
      );

      expect(calls.length, 1);
      expect(calls.first['token'], 'token123');
      expect(calls.first['issuer'], 'issuer123');
      expect(calls.first['audience'], 'aud123');
      expect(calls.first['clockSkew'], 30);
    });

    test('throws TokenValidationException on bridge error', () async {
      expect(
        () => client.verifyToken(token: 'invalid-token'),
        throwsA(isA<TokenValidationException>()),
      );
    });
  });
}
