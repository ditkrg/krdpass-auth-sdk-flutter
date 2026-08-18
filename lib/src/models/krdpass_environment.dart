enum KrdpassEnvironment {
  /// Production environment (app.pass.krd), for live apps.
  production(
    'https://app.pass.krd/connect/authorize',
    'https://account.id.krd',
    'https://app.pass.krd',
  ),

  /// Development environment (app.krdpass.dev.krd), for testing.
  development(
    'https://app.krdpass.dev.krd/connect/authorize',
    'https://auth.dev.krd',
    'https://app.krdpass.dev.krd',
  );

  const KrdpassEnvironment(this.authUrl, this.authServerUrl, this.installUrl);

  final String authUrl;

  final String authServerUrl;

  /// The web URL for this environment: opens the KRDPASS install page when the
  /// app is not present, or the app itself when it is.
  final String installUrl;
}
