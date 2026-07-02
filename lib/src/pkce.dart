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
  /// Prefer using `KrdpassAuth.instance.generatePkcePair()` for generating new pairs.
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

  final Random _random;

  /// Bytes of entropy for verifier (32 bytes = 43 base64url characters).
  static const int _verifierByteLength = 32;

  /// Generates a new RFC 7636 compliant PKCE pair.
  PkcePair generate() {
    final verifierBytes = _generateRandomBytes(_verifierByteLength);
    final codeVerifier = _base64UrlEncodeNoPadding(verifierBytes);
    final codeChallenge = _computeChallenge(codeVerifier);

    return PkcePair(codeVerifier: codeVerifier, codeChallenge: codeChallenge);
  }

  /// Computes the S256 challenge for a given verifier.
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
    // Use Dart's built-in base64Url encoder and strip padding
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
