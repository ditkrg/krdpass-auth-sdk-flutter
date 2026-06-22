import 'auth_result.dart';
import 'krdpass_environment.dart';

/// Configuration for the KRDPass authentication client.
class KrdpassConfig {
  const KrdpassConfig({
    required this.clientId,
    required this.redirectUri,
    this.environment = KrdpassEnvironment.production,
    this.onResult,
    this.stateValidator,
  });

  /// The OAuth client ID.
  final String clientId;

  /// The redirect URI registered with your OAuth provider.
  /// Must be HTTPS and match the host configured for your Universal Links.
  final String redirectUri;

  /// The KRDPass environment to use (production or development).
  final KrdpassEnvironment environment;

  /// Optional callback invoked when an auth result is received.
  final void Function(AuthResult result)? onResult;

  /// Optional callback to validate the state parameter from OAuth responses.
  /// Returns true if the state is valid, false otherwise.
  /// If not provided, state validation is skipped.
  final bool Function(String? state)? stateValidator;

  /// Get the URI scheme from the redirectUri (e.g., "https" from "https://example.com/callback")
  String get redirectScheme {
    final uri = Uri.tryParse(redirectUri);
    return uri?.scheme ?? '';
  }

  /// Get the host from the redirectUri (e.g., "example.com" from "https://example.com/callback")
  String get redirectHost {
    final uri = Uri.tryParse(redirectUri);
    return uri?.host ?? '';
  }

  /// Check if a given URI matches the configured redirect URI pattern.
  ///
  /// Enforces HTTPS-only redirects. Requires host match; path is NOT validated -
  /// any HTTPS path on the same host is allowed.
  bool isValidRedirectUri(Uri uri) {
    final configuredUri = Uri.tryParse(redirectUri);
    if (configuredUri == null) return false;
    if (uri.scheme != 'https') return false;
    if (configuredUri.scheme != 'https') return false;
    if (configuredUri.host.isEmpty) return false;
    if (uri.host.isEmpty) return false;
    if (uri.host != configuredUri.host) return false;

    final configuredPort = configuredUri.hasPort ? configuredUri.port : -1;
    final incomingPort = uri.hasPort ? uri.port : -1;
    if (configuredPort != -1 || incomingPort != -1) {
      if (configuredPort != incomingPort) return false;
    }

    return true;
  }

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
