import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('PKCE Generation', () {
    final generator = PkceGenerator.secure();

    test('generatePkcePair produces valid PKCE pair', () {
      final pkce = generator.generate();

      expect(pkce.codeVerifier, isNotEmpty);
      expect(pkce.codeChallenge, isNotEmpty);
      expect(pkce.method, equals('S256'));

      expect(pkce.codeVerifier.length, greaterThanOrEqualTo(43));
      expect(pkce.codeVerifier.length, lessThanOrEqualTo(128));
      expect(_isValidBase64Url(pkce.codeVerifier), isTrue);

      expect(pkce.codeChallenge.length, greaterThan(0));
      expect(_isValidBase64Url(pkce.codeChallenge), isTrue);
    });

    test('toString leaks no part of the verifier', () {
      // Even a prefix of the PKCE secret in a log is a leak.
      final pkce = generator.generate();

      final text = pkce.toString();
      expect(text, isNot(contains(pkce.codeVerifier)));
      expect(
        text,
        'PkcePair(codeVerifier=[REDACTED], codeChallenge=[REDACTED], method=S256)',
      );
    });

    test('generatePkcePair produces different values each time', () {
      final pkce1 = generator.generate();
      final pkce2 = generator.generate();

      expect(pkce1.codeVerifier, isNot(equals(pkce2.codeVerifier)));
      expect(pkce1.codeChallenge, isNot(equals(pkce2.codeChallenge)));
    });

    test('PKCE challenge matches SHA256 of verifier', () {
      final pkce = generator.generate();

      final expectedChallenge = _computeChallenge(pkce.codeVerifier);

      expect(pkce.codeChallenge, equals(expectedChallenge));
    });

    test('Known test vector', () {
      // RFC 7636 Appendix B test vector
      const testVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      final actualChallenge = _computeChallenge(testVerifier);

      expect(actualChallenge, equals(expectedChallenge));
    });

    test('serialization and deserialization', () {
      final original = generator.generate();

      final json = {
        'codeVerifier': original.codeVerifier,
        'codeChallenge': original.codeChallenge,
        'method': original.method,
      };

      final deserialized = PkcePair.fromJson(json);

      expect(deserialized.codeVerifier, equals(original.codeVerifier));
      expect(deserialized.codeChallenge, equals(original.codeChallenge));
      expect(deserialized.method, equals(original.method));
    });

    test('equality and hashCode', () {
      const pkce1 = PkcePair(
        codeVerifier: 'verifier1',
        codeChallenge: 'challenge1',
      );
      const pkce2 = PkcePair(
        codeVerifier: 'verifier1',
        codeChallenge: 'challenge1',
      );
      const pkce3 = PkcePair(
        codeVerifier: 'verifier2',
        codeChallenge: 'challenge1',
      );

      expect(pkce1, equals(pkce2));
      expect(pkce1, isNot(equals(pkce3)));
      expect(pkce1.hashCode, equals(pkce2.hashCode));
    });
  });
}

bool _isValidBase64Url(String str) {
  final base64UrlRegex = RegExp(r'^[A-Za-z0-9_-]+$');
  return base64UrlRegex.hasMatch(str);
}

String _computeChallenge(String verifier) {
  final challengeBytes = sha256.convert(utf8.encode(verifier)).bytes;
  return _base64UrlEncodeForTest(challengeBytes);
}

String _base64UrlEncodeForTest(List<int> bytes) {
  final base64 = base64Encode(bytes);
  return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
