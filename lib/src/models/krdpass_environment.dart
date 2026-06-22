/// Defines the KRDPass environment to use for authentication.
enum KrdpassEnvironment {
  /// Production environment (app.pass.krd).
  /// Use this for live apps distributed to end users.
  production(
    'https://app.pass.krd/connect/authorize',
    'https://account.id.krd',
  ),

  /// Development environment (app.krdpass.dev.krd).
  /// Use this for testing and development.
  development(
    'https://app.krdpass.dev.krd/connect/authorize',
    'https://auth.dev.krd',
  );

  const KrdpassEnvironment(this.authUrl, this.authServerUrl);

  /// The authorization URL for this environment.
  final String authUrl;

  /// The authorization server URL for this environment.
  final String authServerUrl;

  /// The UserInfo endpoint URL for this environment.
  String get userInfoEndpoint => '$authServerUrl/connect/userinfo';

  /// The Token endpoint URL for this environment (used for token exchange and refresh).
  String get tokenEndpoint => '$authServerUrl/connect/token';

  /// The Revocation endpoint URL for this environment.
  String get revocationEndpoint => '$authServerUrl/connect/revocation';

  /// The PAR (Pushed Authorization Request) endpoint URL for this environment.
  String get parEndpoint => '$authServerUrl/connect/par';

  /// The JWKS (JSON Web Key Set) endpoint URL for this environment.
  String get jwksEndpoint =>
      '$authServerUrl/.well-known/openid-configuration/jwks';
}
