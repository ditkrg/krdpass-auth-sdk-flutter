import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';
// src import: the test needs all eleven strings, not just the exported ones.
import 'package:krdpass_auth_flutter/src/messages.dart';

/// Locks the canonical error strings, which must stay byte-identical with the
/// iOS/Android/RN SDKs.
void main() {
  group('canonical messages', () {
    // The literals are the contract: do not rewrite them in terms of the kMsg
    // constants, a test comparing a constant to itself cannot catch drift.
    test('the full canonical set is byte-identical with the other SDKs', () {
      expect(kMsgCancelled, 'Authentication was cancelled');
      expect(kMsgTimeout, 'Authentication timed out');
      expect(kMsgBusy, 'Another authentication is already in progress');
      expect(
        kMsgProviderNotInstalled,
        'The KRDPASS app is not installed or could not be opened. Please install or update KRDPASS.',
      );
      expect(
        kMsgStateMismatch,
        'State parameter mismatch: possible CSRF or response injection',
      );
      expect(
        kMsgIssuerMismatch,
        'Issuer mismatch: the response did not come from the expected authorization server',
      );
      expect(kMsgNoCode, 'No authorization code received');
      expect(
        kMsgInvalidRedirect,
        'Redirect URI does not match the exact configured endpoint',
      );
      expect(
        kMsgStateRequired,
        "state is required and cannot be blank. Pass the state returned by your backend's PAR call, or use signIn().",
      );
      expect(kMsgMissingIdToken, 'Token response did not include an id_token');
      expect(
        kMsgNonceMismatch,
        'ID token nonce mismatch (possible token replay)',
      );
    });

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

    // Each plugin hand-copies this string in its own language, and the Swift one has no test
    // target in this repo, so the sources are the only place the three can be compared.
    test('the state-required string appears verbatim in both plugin sources', () {
      String joinAdjacentLiterals(String source) =>
          source.replaceAll(RegExp(r'"\s*\+\s*"'), '');

      final kotlin = joinAdjacentLiterals(
        File(
          'android/src/main/kotlin/krd/pass/auth/KrdpassAuthPlugin.kt',
        ).readAsStringSync(),
      );
      final swift = joinAdjacentLiterals(
        File(
          'ios/krdpass_auth_flutter/Sources/krdpass_auth_flutter/KrdpassAuthPlugin.swift',
        ).readAsStringSync(),
      );

      expect(kotlin, contains(kMsgStateRequired));
      expect(swift, contains(kMsgStateRequired));
    });
  });
}
