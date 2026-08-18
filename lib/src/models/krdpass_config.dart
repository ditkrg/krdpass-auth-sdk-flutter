import 'krdpass_environment.dart';

class KrdpassConfig {
  const KrdpassConfig({
    required this.clientId,
    required this.redirectUri,
    this.environment = KrdpassEnvironment.production,
  });

  final String clientId;

  /// Must be HTTPS and match the host configured for your Universal Links.
  final String redirectUri;

  final KrdpassEnvironment environment;

  /// Throws if [clientId] is empty or [redirectUri] is not an HTTPS URL with
  /// a host.
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
