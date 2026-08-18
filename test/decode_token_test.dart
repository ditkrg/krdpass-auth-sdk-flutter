import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

/// Coverage for the publicly-exported unverified-decode helper (display-only).
void main() {
  final client = KrdpassAuth.instance;

  // base64url-encode a JSON object the way a JWT payload segment is encoded.
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');

  group('decodeTokenUnverified', () {
    test('decodes JWT claims', () {
      final token = 'header.${segment({'sub': '123', 'scope': 'openid'})}.sig';
      final claims = client.decodeTokenUnverified(token);
      expect(claims['sub'], '123');
      expect(claims['scope'], 'openid');
    });

    test('preserves non-ASCII (Kurdish/Arabic) claims as UTF-8', () {
      const name = 'ئارین کابان';
      final token = 'header.${segment({'name': name})}.sig';
      expect(client.decodeTokenUnverified(token)['name'], name);
    });

    test('throws on an empty token', () {
      expect(() => client.decodeTokenUnverified(''), throwsFormatException);
    });

    test('throws on a single-segment token', () {
      expect(
        () => client.decodeTokenUnverified('onlyonepart'),
        throwsFormatException,
      );
    });

    test('throws on an unparseable payload', () {
      expect(
        () => client.decodeTokenUnverified('header.!!!notbase64!!!.sig'),
        throwsFormatException,
      );
    });
  });
}
