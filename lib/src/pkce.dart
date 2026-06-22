import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A PKCE (Proof Key for Code Exchange) code verifier and challenge pair.
///
/// Implements RFC 7636 compliant PKCE flow with S256 challenge method.
///
/// ## Example
/// ```dart
/// final pkce = KrdpassAuth.instance.generatePkcePair();
///
/// // Send pkce.codeChallenge to your backend's PAR endpoint when starting the flow,
/// // and keep pkce.codeVerifier to send when your backend exchanges the code.
/// ```
class PkcePair {
  /// Creates a PKCE pair with the given values.
  ///
  /// Prefer using [generatePkcePair] for generating new pairs.
  /// Use this constructor for testing or reconstructing from storage.
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

  /// The code verifier (43-128 characters, base64url alphabet).
  ///
  /// Store securely and send when exchanging the authorization code.
  final String codeVerifier;

  /// The code challenge (base64url-encoded SHA256 hash of verifier).
  ///
  /// Send when initiating the authorization request.
  final String codeChallenge;

  /// The challenge method (always 'S256' for this implementation).
  final String method;

  /// Minimum verifier length per RFC 7636.
  static const int minVerifierLength = 43;

  /// Maximum verifier length per RFC 7636.
  static const int maxVerifierLength = 128;

  @override
  String toString() {
    String truncate(String value) =>
        value.length >= 8 ? '${value.substring(0, 8)}...' : value;

    return 'PkcePair('
        'verifier: ${truncate(codeVerifier)}, '
        'challenge: ${truncate(codeChallenge)}, '
        'method: $method)';
  }

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

/// Generates a PKCE code verifier and challenge pair.
///
/// Uses RFC 7636 compliant S256 method with cryptographically secure
/// random number generation.
PkcePair generatePkcePair() => PkceGenerator.secure().generate();

/// Utility class for generating PKCE pairs.
///
/// Supports dependency injection of [Random] for deterministic testing.
class PkceGenerator {
  /// Creates a generator with the specified random source.
  const PkceGenerator(this._random);

  /// Creates a generator with cryptographically secure random.
  ///
  /// Use this for production code.
  factory PkceGenerator.secure() => PkceGenerator(Random.secure());

  /// Creates a generator with a seeded random for testing.
  ///
  /// **Warning:** Only use for testing. Not cryptographically secure.
  factory PkceGenerator.seeded(int seed) => PkceGenerator(Random(seed));

  final Random _random;

  /// Bytes of entropy for verifier (32 bytes = 43 base64url characters).
  static const int _verifierByteLength = 32;

  /// Generates a new RFC 7636 compliant PKCE pair.
  PkcePair generate() {
    final verifierBytes = _generateRandomBytes(_verifierByteLength);
    final codeVerifier = _base64UrlEncodeNoPadding(verifierBytes);
    final codeChallenge = computeChallenge(codeVerifier);

    return PkcePair(codeVerifier: codeVerifier, codeChallenge: codeChallenge);
  }

  /// Computes the S256 challenge for a given verifier.
  ///
  /// Useful for validation or creating pairs from existing verifiers.
  static String computeChallenge(String verifier) {
    final hash = sha256.convert(utf8.encode(verifier));
    return _base64UrlEncodeNoPadding(hash.bytes);
  }

  /// Generates a cryptographically secure, URL-safe random token.
  ///
  /// Use this for the OAuth `state` (CSRF) parameter. It is independent of PKCE
  /// so the `state` value is never derived from or confused with a code verifier.
  static String generateSecureToken([int byteLength = 32]) {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(byteLength, (_) => random.nextInt(256)),
    );
    return _base64UrlEncodeNoPadding(bytes);
  }

  Uint8List _generateRandomBytes(int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static String _base64UrlEncodeNoPadding(List<int> bytes) {
    // Use Dart's built-in base64Url encoder and strip padding
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
