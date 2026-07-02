/// Defines the KRDPASS environment to use for authentication.
enum KrdpassEnvironment {
  /// Production environment (app.pass.krd).
  /// Use this for live apps distributed to end users.
  production(
    'https://app.pass.krd/connect/authorize',
    'https://account.id.krd',
    'https://app.pass.krd',
  ),

  /// Development environment (app.krdpass.dev.krd).
  /// Use this for testing and development.
  development(
    'https://app.krdpass.dev.krd/connect/authorize',
    'https://auth.dev.krd',
    'https://app.krdpass.dev.krd',
  );

  const KrdpassEnvironment(this.authUrl, this.authServerUrl, this.installUrl);

  /// The authorization URL for this environment.
  final String authUrl;

  /// The authorization server URL for this environment.
  final String authServerUrl;

  /// The web URL for this environment. Opening it in a browser takes users to the KRDPASS
  /// install page when the app is not present, or opens the app if already installed.
  /// Surface this when returning a `provider_not_installed` error so integrators can prompt
  /// the user to install KRDPASS.
  final String installUrl;
}
