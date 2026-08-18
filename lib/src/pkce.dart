import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An RFC 7636 PKCE code verifier and challenge pair (S256).
class PkcePair {
  /// Prefer `KrdpassAuth.instance.generatePkcePair()`; use this constructor
  /// for testing or reconstructing from storage.
  const PkcePair({
    required this.codeVerifier,
    required this.codeChallenge,
    this.method = 'S256',
  });

  /// Deserializes a PKCE pair from a JSON map.
  factory PkcePair.fromJson(Map<String, dynamic> json) => PkcePair(
    codeVerifier: json['codeVerifier'] as String,
    codeChallenge: json['codeChallenge'] as String,
    method: json['method'] as String? ?? 'S256',
  );

  /// The code verifier (43-128 characters, base64url alphabet). Store securely
  /// and send when exchanging the authorization code.
  final String codeVerifier;

  /// The code challenge (base64url-encoded SHA256 hash of the verifier).
  final String codeChallenge;

  /// The challenge method (always 'S256').
  final String method;

  /// Fully redacted, matching the native cores: even a prefix of the verifier
  /// is a prefix of a secret in a log or crash report.
  @override
  String toString() =>
      'PkcePair(codeVerifier=[REDACTED], codeChallenge=[REDACTED], method=$method)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PkcePair &&
          runtimeType == other.runtimeType &&
          codeVerifier == other.codeVerifier &&
          codeChallenge == other.codeChallenge &&
          method == other.method;

  @override
  int get hashCode => Object.hash(codeVerifier, codeChallenge, method);
}

/// Generates PKCE pairs. The random source is not injectable: a predictable
/// code verifier defeats the point of PKCE.
class PkceGenerator {
  const PkceGenerator._(this._random);

  /// Creates a generator backed by a cryptographically secure random source.
  factory PkceGenerator.secure() => PkceGenerator._(Random.secure());

  final Random _random;

  /// 32 bytes of entropy = 43 base64url characters.
  static const int _verifierByteLength = 32;

  /// Generates a new RFC 7636 compliant PKCE pair.
  PkcePair generate() {
    final codeVerifier = randomUrlSafeToken(_verifierByteLength);
    final codeChallenge = _computeChallenge(codeVerifier);

    return PkcePair(codeVerifier: codeVerifier, codeChallenge: codeChallenge);
  }

  /// [byteLength] random bytes, base64url-encoded without padding. The shared
  /// primitive behind code verifiers and `generateState`, matching the native
  /// cores' randomUrlSafeToken.
  String randomUrlSafeToken(int byteLength) =>
      _base64UrlEncodeNoPadding(_generateRandomBytes(byteLength));

  static String _computeChallenge(String verifier) {
    final hash = sha256.convert(utf8.encode(verifier));
    return _base64UrlEncodeNoPadding(hash.bytes);
  }

  Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static String _base64UrlEncodeNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
