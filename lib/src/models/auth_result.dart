import '../messages.dart';

/// Native error codes the SDK treats as a user cancellation. Shared by the
/// result mapping, the exception mapping, and [AuthResult.isCancelled] so the
/// same code cannot classify differently on the authenticate vs signIn path.
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

  const AuthResult.success({required String code, String? state})
    : this._(code: code, state: state);

  /// The KRDPASS app is not installed or could not be opened. Open [installUrl]
  /// in a browser to direct the user to the app store.
  const AuthResult.providerNotInstalled({String? installUrl})
    : this._(
        error: 'provider_not_installed',
        errorDescription: kMsgProviderNotInstalled,
        installUrl: installUrl,
      );

  /// Authentication failed due to state mismatch.
  const AuthResult.stateMismatch({String? errorDescription})
    : this._(
        error: 'state_mismatch',
        errorDescription: errorDescription ?? kMsgStateMismatch,
      );

  /// [errorDescription] keeps the provider's own reason from the redirect when
  /// present, the one diagnostic a cancelled flow has. [state] is a second line of
  /// defence only: the cores already reject a mismatched one before it reaches Dart,
  /// and neither bridge currently sends it on a non-success result.
  const AuthResult.cancelled({String? errorDescription, String? state})
    : this._(
        error: 'cancelled',
        errorDescription: errorDescription ?? kMsgCancelled,
        state: state,
      );

  const AuthResult.timeout()
    : this._(error: 'timeout', errorDescription: kMsgTimeout);

  const AuthResult.busy() : this._(error: 'busy', errorDescription: kMsgBusy);

  const AuthResult.platformError(String reason)
    : this._(error: 'platform_error', errorDescription: reason);

  /// [state] is a second line of defence only: the cores already reject a mismatched
  /// one before it reaches Dart, and neither bridge currently sends it here.
  const AuthResult.error({
    required String error,
    String? errorDescription,
    String? state,
  }) : this._(error: error, errorDescription: errorDescription, state: state);

  final String? code;

  final String? state;

  final String? error;

  final String? errorDescription;

  /// The KRDPASS install URL, populated when [error] is `provider_not_installed`.
  final String? installUrl;

  bool get isSuccess => code != null && error == null;

  bool get isError => error != null;

  bool get isCancelled => kCancelledCodes.contains(error);

  bool get isTimeout => error == 'timeout';

  bool get isBusy => error == 'busy';

  bool get isStateMismatch => error == 'state_mismatch';

  bool get isProviderNotInstalled => error == 'provider_not_installed';

  String get errorMessage =>
      errorDescription ?? error ?? 'Unknown authentication error';

  @override
  String toString() {
    if (isSuccess) {
      return 'AuthResult.success(code: [REDACTED], state: [REDACTED])';
    }
    return 'AuthResult.error(error: $error, errorDescription: $errorDescription)';
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
      Object.hash(code, state, error, errorDescription, installUrl);
}
