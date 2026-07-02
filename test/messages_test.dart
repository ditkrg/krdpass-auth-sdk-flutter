import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

/// Locks the canonical, cross-platform error strings. These must stay
/// byte-identical with the iOS/Android/RN SDKs, see each SDK's equivalent test.
/// Both auth APIs (signIn throws / authenticate returns) must surface the same text.
void main() {
  group('canonical messages', () {
    test('signIn exceptions carry the canonical text', () {
      expect(
        const KrdpassCancelledException().message,
        'Authentication was cancelled',
      );
      expect(
        const KrdpassTimeoutException().message,
        'Authentication timed out',
      );
      expect(
        const KrdpassBusyException().message,
        'Another authentication is already in progress',
      );
    });

    test('authenticate AuthResult surfaces the same text', () {
      expect(
        const AuthResult.cancelled().errorMessage,
        'Authentication was cancelled',
      );
      expect(
        const AuthResult.timeout().errorMessage,
        'Authentication timed out',
      );
      expect(
        const AuthResult.busy().errorMessage,
        'Another authentication is already in progress',
      );
    });

    test('state-related canonical strings', () {
      expect(
        const AuthResult.stateMismatch().errorMessage,
        'State parameter mismatch: possible CSRF or response injection',
      );
      expect(
        const AuthResult.providerNotInstalled().errorMessage,
        'The KRDPASS app is not installed or could not be opened. Please install or update KRDPASS.',
      );
    });
  });
}
