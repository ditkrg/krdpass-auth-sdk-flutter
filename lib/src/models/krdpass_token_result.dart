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
      accessToken: json['accessToken'] ?? json['access_token'] ?? '',
      tokenType: json['tokenType'] ?? json['token_type'] ?? 'Bearer',
      expiresIn: json['expiresIn'] ?? json['expires_in'] ?? 3600,
      idToken: json['idToken'] ?? json['id_token'],
      refreshToken: json['refreshToken'] ?? json['refresh_token'],
      scope: json['scope'],
      receivedAt: json['receivedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['receivedAt'])
          : (json['received_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(json['received_at'])
              : null),
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

  /// The time when the tokens were received.
  final DateTime? receivedAt;

  /// Returns the actual [receivedAt] time, defaulting to now if not set.
  DateTime get receivedAtOrDefault => receivedAt ?? DateTime.now();

  /// Whether the access token is expired or will expire within the given clock skew.
  bool isExpired({Duration skew = const Duration(minutes: 1)}) {
    final expirationDate =
        receivedAtOrDefault.add(Duration(seconds: expiresIn));
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
}
