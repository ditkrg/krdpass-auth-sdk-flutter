/// Result of a KRDPass authentication attempt.
class AuthResult {
  const AuthResult._({
    this.code,
    this.state,
    this.rawRedirectUri,
    this.error,
    this.errorDescription,
  });

  /// Authentication was successful.
  const AuthResult.success({
    required String code,
    String? state,
    Uri? rawRedirectUri,
  }) : this._(code: code, state: state, rawRedirectUri: rawRedirectUri);

  /// Authentication failed due to invalid redirect URI.
  const AuthResult.invalidRedirect({String? errorDescription})
      : this._(
          error: 'invalid_redirect',
          errorDescription:
              errorDescription ?? 'Redirect URI does not match expected format',
        );

  /// Authentication failed due to state mismatch.
  const AuthResult.stateMismatch({String? errorDescription})
      : this._(
          error: 'state_mismatch',
          errorDescription: errorDescription ??
              'State parameter does not match expected value',
        );

  /// Authentication was cancelled by the user.
  const AuthResult.cancelled()
      : this._(
          error: 'cancelled',
          errorDescription: 'Authentication was cancelled by the user',
        );

  /// Authentication timed out.
  const AuthResult.timeout()
      : this._(error: 'timeout', errorDescription: 'Authentication timed out');

  /// Another authentication is already in progress.
  const AuthResult.busy()
      : this._(
          error: 'busy',
          errorDescription: 'Another authentication is already in progress',
        );

  /// Platform-specific error occurred.
  const AuthResult.platformError(String reason)
      : this._(error: 'platform_error', errorDescription: reason);

  /// Generic authentication error.
  const AuthResult.error({required String error, String? errorDescription})
      : this._(error: error, errorDescription: errorDescription);

  /// The authorization code received on success.
  final String? code;

  /// The state parameter from the OAuth flow.
  final String? state;

  /// The raw redirect URI received (for debugging, not for production use).
  final Uri? rawRedirectUri;

  /// Error code if authentication failed.
  final String? error;

  /// Human-readable error description.
  final String? errorDescription;

  /// True if authentication was successful (code received).
  bool get isSuccess => code != null && error == null;

  /// True if an error occurred.
  bool get isError => error != null;

  /// True if the user cancelled the authentication.
  bool get isCancelled => error == 'cancelled' || error == 'access_denied';

  /// True if the authentication timed out.
  bool get isTimeout => error == 'timeout';

  /// True if another authentication is already in progress.
  bool get isBusy => error == 'busy';

  /// True if the redirect URI was invalid.
  bool get isInvalidRedirect => error == 'invalid_redirect';

  /// True if the state parameter didn't match.
  bool get isStateMismatch => error == 'state_mismatch';

  /// Human-readable error message.
  String get errorMessage =>
      errorDescription ?? error ?? 'Unknown authentication error';

  @override
  String toString() {
    if (isSuccess) {
      return 'AuthResult.success(code: [REDACTED], state: [REDACTED])';
    }
    return 'AuthResult.$error(error: $error)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthResult &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          state == other.state &&
          rawRedirectUri == other.rawRedirectUri &&
          error == other.error &&
          errorDescription == other.errorDescription;

  @override
  int get hashCode =>
      code.hashCode ^
      state.hashCode ^
      rawRedirectUri.hashCode ^
      error.hashCode ^
      errorDescription.hashCode;
}
