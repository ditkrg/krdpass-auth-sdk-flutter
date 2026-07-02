import '../messages.dart';

/// Native error codes the SDK treats as a user cancellation (the OIDC
/// `login_required`/`consent_denied` count too). Shared by the result mapping,
/// the exception mapping, and [AuthResult.isCancelled] so the same native code
/// can't classify differently on the authenticate vs signIn path.
const Set<String> kCancelledCodes = {
  'cancelled',
  'user_cancelled',
  'access_denied',
  'login_required',
  'consent_denied',
};

/// Result of a KRDPASS authentication attempt.
class AuthResult {
  const AuthResult._({
    this.code,
    this.state,
    this.error,
    this.errorDescription,
    this.installUrl,
  });

  /// Authentication was successful.
  const AuthResult.success({required String code, String? state})
    : this._(code: code, state: state);

  /// The KRDPASS app is not installed or could not be opened via Universal Link / App Link.
  /// [installUrl] is the environment's web URL: open it in a browser to direct the user to
  /// the app store, or to open the app if already installed.
  const AuthResult.providerNotInstalled({String? installUrl})
    : this._(
        error: 'provider_not_installed',
        errorDescription:
            'The KRDPASS app is not installed or could not be opened. Please install or update KRDPASS.',
        installUrl: installUrl,
      );

  /// Authentication failed due to state mismatch.
  const AuthResult.stateMismatch({String? errorDescription})
    : this._(
        error: 'state_mismatch',
        errorDescription:
            errorDescription ??
            'State parameter mismatch: possible CSRF or response injection',
      );

  /// Authentication was cancelled by the user.
  const AuthResult.cancelled()
    : this._(error: 'cancelled', errorDescription: kMsgCancelled);

  /// Authentication timed out.
  const AuthResult.timeout()
    : this._(error: 'timeout', errorDescription: kMsgTimeout);

  /// Another authentication is already in progress.
  const AuthResult.busy() : this._(error: 'busy', errorDescription: kMsgBusy);

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

  /// Error code if authentication failed.
  final String? error;

  /// Human-readable error description.
  final String? errorDescription;

  /// The KRDPASS install URL, populated when [error] is `provider_not_installed`.
  /// Open this URL in a browser to take the user to the app store (or open the app
  /// if already installed).
  final String? installUrl;

  /// True if authentication was successful (code received).
  bool get isSuccess => code != null && error == null;

  /// True if an error occurred.
  bool get isError => error != null;

  /// True if the user cancelled the authentication.
  bool get isCancelled => kCancelledCodes.contains(error);

  /// True if the authentication timed out.
  bool get isTimeout => error == 'timeout';

  /// True if another authentication is already in progress.
  bool get isBusy => error == 'busy';

  /// True if the state parameter didn't match.
  bool get isStateMismatch => error == 'state_mismatch';

  /// True if the KRDPASS app is not installed (or could not be launched via App Link).
  bool get isProviderNotInstalled => error == 'provider_not_installed';

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
          error == other.error &&
          errorDescription == other.errorDescription &&
          installUrl == other.installUrl;

  @override
  int get hashCode =>
      code.hashCode ^
      state.hashCode ^
      error.hashCode ^
      errorDescription.hashCode ^
      installUrl.hashCode;
}
