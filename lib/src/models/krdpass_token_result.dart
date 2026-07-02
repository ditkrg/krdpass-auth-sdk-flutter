/// Result containing tokens from a successful client-only authentication.
///
/// This is returned by [KrdpassAuth.signIn] when the SDK
/// handles PAR and token exchange directly with CAS.
class KrdpassTokenResult {
  const KrdpassTokenResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.idToken,
    this.refreshToken,
    this.scope,
    this.receivedAt,
  });

  /// Create a [KrdpassTokenResult] from a map of JSON data.
  /// Handles both camelCase and snake_case keys.
  factory KrdpassTokenResult.fromJson(Map<String, dynamic> json) {
    return KrdpassTokenResult(
      accessToken:
          (json['accessToken'] ?? json['access_token']) as String? ?? '',
      tokenType:
          (json['tokenType'] ?? json['token_type']) as String? ?? 'Bearer',
      expiresIn:
          ((json['expiresIn'] ?? json['expires_in']) as num?)?.toInt() ?? 3600,
      idToken: (json['idToken'] ?? json['id_token']) as String?,
      refreshToken: (json['refreshToken'] ?? json['refresh_token']) as String?,
      scope: json['scope'] as String?,
      // receivedAt is deliberately NOT read from the map: it's a LOCAL clock stamp (when THIS
      // device received the token). A backend-echoed value would conflate two clocks and corrupt
      // isExpired(). Stamped here at parse time, matching the Android/iOS/RN SDKs.
      receivedAt: DateTime.now(),
    );
  }

  /// The access token for API calls.
  final String accessToken;

  /// The ID token containing user identity claims (if requested).
  final String? idToken;

  /// The token type (usually "Bearer").
  final String tokenType;

  /// Token expiration time in seconds.
  final int expiresIn;

  /// The refresh token for obtaining new access tokens (if provided).
  final String? refreshToken;

  /// The scope granted by the authorization server.
  final String? scope;

  /// The time when the tokens were received. Always stamped by [fromJson]; only null for
  /// hand-constructed instances.
  final DateTime? receivedAt;

  /// Returns the actual [receivedAt] time, defaulting to now if not set.
  ///
  /// Note: for a hand-constructed instance with no [receivedAt], this re-evaluates
  /// `DateTime.now()` per call, so [isExpired] can never trip. Always let [fromJson]
  /// stamp receipt time (as the SDK's own flows do).
  DateTime get receivedAtOrDefault => receivedAt ?? DateTime.now();

  /// Whether the access token is expired or will expire within the given clock skew.
  bool isExpired({Duration skew = const Duration(minutes: 1)}) {
    final expirationDate = receivedAtOrDefault.add(
      Duration(seconds: expiresIn),
    );
    return DateTime.now().add(skew).isAfter(expirationDate);
  }

  @override
  String toString() {
    return 'KrdpassTokenResult('
        'accessToken: [REDACTED], '
        'idToken: ${idToken != null ? "[REDACTED]" : "null"}, '
        'tokenType: $tokenType, '
        'expiresIn: $expiresIn, '
        'refreshToken: ${refreshToken != null ? "[REDACTED]" : "null"}, '
        'scope: $scope'
        ')';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KrdpassTokenResult &&
          runtimeType == other.runtimeType &&
          accessToken == other.accessToken &&
          idToken == other.idToken &&
          tokenType == other.tokenType &&
          expiresIn == other.expiresIn &&
          refreshToken == other.refreshToken &&
          scope == other.scope &&
          receivedAt == other.receivedAt;

  @override
  int get hashCode => Object.hash(
    accessToken,
    idToken,
    tokenType,
    expiresIn,
    refreshToken,
    scope,
    receivedAt,
  );
}
