/// Tokens from a successful client-only authentication ([KrdpassAuth.signIn]).
class KrdpassTokenResult {
  KrdpassTokenResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.idToken,
    this.refreshToken,
    this.scope,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Parses both camelCase and snake_case keys. Throws [FormatException] when
  /// `access_token` or `expires_in` is missing: a truncated bridge payload
  /// must not parse as a usable credential.
  factory KrdpassTokenResult.fromJson(Map<String, dynamic> json) {
    final accessToken =
        (json['accessToken'] ?? json['access_token']) as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException(
        'Invalid token response: missing or empty access_token',
      );
    }
    final expiresIn = ((json['expiresIn'] ?? json['expires_in']) as num?)
        ?.toInt();
    if (expiresIn == null) {
      throw const FormatException('Invalid token response: missing expires_in');
    }

    return KrdpassTokenResult(
      accessToken: accessToken,
      tokenType:
          (json['tokenType'] ?? json['token_type']) as String? ?? 'Bearer',
      expiresIn: expiresIn,
      idToken: (json['idToken'] ?? json['id_token']) as String?,
      refreshToken: (json['refreshToken'] ?? json['refresh_token']) as String?,
      scope: json['scope'] as String?,
      // Local clock stamp, never read from the map: a backend-echoed value would
      // mix two clocks and corrupt isExpired().
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

  /// The local clock time when the tokens were received; stamped at
  /// construction when not supplied, so [isExpired] always has a reference.
  final DateTime receivedAt;

  /// Whether the access token is expired or will expire within [skew].
  ///
  /// `!isBefore` so the exact expiry instant counts as expired, matching the
  /// native cores' `>=`.
  bool isExpired({Duration skew = const Duration(minutes: 1)}) {
    final expirationDate = receivedAt.add(Duration(seconds: expiresIn));
    return !DateTime.now().add(skew).isBefore(expirationDate);
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

  /// Value equality over every field, [receivedAt] included: two results parsed
  /// from the same response are NOT equal, each carries its own clock stamp.
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
