import 'krdpass_environment.dart';

/// Configuration for the KRDPASS authentication client.
class KrdpassConfig {
  const KrdpassConfig({
    required this.clientId,
    required this.redirectUri,
    this.environment = KrdpassEnvironment.production,
  });

  /// The OAuth client ID.
  final String clientId;

  /// The redirect URI registered with your OAuth provider.
  /// Must be HTTPS and match the host configured for your Universal Links.
  final String redirectUri;

  /// The KRDPASS environment to use (production or development).
  final KrdpassEnvironment environment;

  /// Validate the configuration.
  ///
  /// Throws [ArgumentError] or [StateError] if the configuration is invalid.
  /// - [clientId] must not be empty
  /// - [redirectUri] must be a valid HTTPS URL with a host
  void validate() {
    if (clientId.isEmpty) {
      throw ArgumentError.value(
        clientId,
        'clientId',
        'Client ID cannot be empty',
      );
    }

    if (redirectUri.isEmpty) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'Redirect URI cannot be empty',
      );
    }

    final uri = Uri.tryParse(redirectUri);
    if (uri == null) {
      throw FormatException('Invalid redirect URI format', redirectUri);
    }

    if (uri.scheme != 'https') {
      throw StateError(
        'Redirect URI must use HTTPS scheme (got: ${uri.scheme})',
      );
    }

    if (uri.host.isEmpty) {
      throw StateError('Redirect URI must have a valid host');
    }
  }
}
