import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassAuthClient Lifecycle', () {
    test('state validation works correctly', () {
      final config = KrdpassConfig(
        redirectUri: 'https://example.com/callback',
        clientId: 'test-client-id',
        stateValidator: (state) => state == 'valid-state',
      );

      expect(config.stateValidator!('valid-state'), isTrue);
      expect(config.stateValidator!('invalid-state'), isFalse);
      expect(config.stateValidator!(null), isFalse);
    });
  });
}
