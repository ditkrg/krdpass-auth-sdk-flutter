import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'logger.dart';
import 'messages.dart';
import 'models/auth_result.dart';
import 'models/krdpass_config.dart';
import 'models/krdpass_scopes.dart';
import 'models/krdpass_token_result.dart';
import 'models/krdpass_user_info.dart';
import 'pkce.dart';
import 'platform/method_channel_krdpass_platform.dart';

/// Main SDK class for Sign in with KRDPASS. Call [initialize] before use.
class KrdpassAuth {
  KrdpassAuth._();
  static final KrdpassAuth _instance = KrdpassAuth._();

  static KrdpassAuth get instance => _instance;

  KrdpassConfig? _config;
  MethodChannelKrdpassPlatform? _platform;

  Completer<AuthResult>? _pendingCompleter;
  bool _isAuthenticating = false;
  String? _expectedState;

  /// The current configuration. Throws [StateError] if not initialized.
  KrdpassConfig get config {
    if (_config == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }
    return _config!;
  }

  /// Captures the non-null platform reference so it survives an `await` even
  /// if [dispose] nulls `_platform` mid-flight.
  MethodChannelKrdpassPlatform get _requirePlatform {
    final platform = _platform;
    if (platform == null || _config == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }
    return platform;
  }

  /// Initialize the SDK. Must be called once, typically at app startup.
  ///
  /// Calling it again replaces the platform bridge, so any flow still in
  /// flight is torn down first and its caller gets a cancellation instead of
  /// hanging until the timeout.
  Future<void> initialize({required KrdpassConfig config}) async {
    config.validate();
    // Checked before any state is written, so a throw leaves the instance untouched.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError(
        'Platform $defaultTargetPlatform is not supported',
      );
    }
    if (_platform != null) dispose();
    _config = config;
    _platform = MethodChannelKrdpassPlatform(config: config);
    _platform!.resultHandler = _completeFromWire;
  }

  /// Generate a cryptographically secure random state string for CSRF protection.
  ///
  /// Only useful when your app, not your backend, chooses the `state` for the
  /// PAR request; if your backend builds the PAR request, pass its state to
  /// [authenticate] instead.
  String generateState() => PkceGenerator.secure().randomUrlSafeToken(32);

  PkcePair generatePkcePair() {
    return PkceGenerator.secure().generate();
  }

  Future<AuthResult> authenticate({
    required String requestUri,
    String? state,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final platform = _requirePlatform;

    if (requestUri.isEmpty) {
      return const AuthResult.platformError('requestUri cannot be empty');
    }
    if (timeout.isNegative || timeout == Duration.zero) {
      return const AuthResult.platformError('timeout must be positive');
    }
    // state is mandatory for CSRF / response-injection protection.
    if (state == null || state.trim().isEmpty) {
      return const AuthResult.error(
        error: 'invalid_request',
        errorDescription: kMsgStateRequired,
      );
    }

    if (_isAuthenticating || _pendingCompleter != null) {
      return const AuthResult.busy();
    }

    _isAuthenticating = true;
    _expectedState = state;
    final owner = Completer<AuthResult>();
    _pendingCompleter = owner;
    final completerFuture = owner.future;

    // Started before the launch so the native round trip counts against the timeout.
    final elapsed = Stopwatch()..start();

    try {
      await platform.authenticate(
        requestUri: requestUri,
        state: state,
        timeout: timeout,
      );

      final remaining = timeout - elapsed.elapsed;
      return await completerFuture.timeout(
        remaining.isNegative ? Duration.zero : remaining,
      );
    } on TimeoutException {
      // Ensure native side is also cancelled/timed out so retries are not blocked by "busy".
      try {
        await platform.cancelPending(timeout: true);
      } catch (e) {
        KrdpassLogger.warning('Failed to timeout native auth flow: $e');
      }
      return _settle(const AuthResult.timeout(), owner: owner);
    } on PlatformException catch (e) {
      // Synchronous channel failures keep the same wire-code taxonomy as results
      // arriving via 'onAuthResult'.
      return _settle(
        platform.createAuthResult(error: e.code, errorDescription: e.message),
        owner: owner,
      );
    } catch (e) {
      KrdpassLogger.error('Authentication failed', e);
      // Canonical text only: `e` can carry a raw native body, and errorDescription
      // is what apps display.
      return _settle(
        const AuthResult.platformError('Authentication failed'),
        owner: owner,
      );
    }
  }

  /// Cancel any in-flight authentication flow ([authenticate] or [signIn]).
  ///
  /// Completes the pending request as [AuthResult.cancelled], or as
  /// [AuthResult.timeout] when [timeout] is true.
  Future<void> cancelPendingAuthentication({bool timeout = false}) async {
    final completer = _pendingCompleter;
    final hasPendingAuthenticate = completer != null && !completer.isCompleted;
    if (!_isAuthenticating && !hasPendingAuthenticate) return;

    try {
      await _platform?.cancelPending(timeout: timeout);
    } catch (e) {
      // Best-effort; still complete locally so callers can retry immediately.
      KrdpassLogger.warning('Failed to cancel native auth flow: $e');
    }

    if (hasPendingAuthenticate) {
      _completeLocal(
        timeout ? const AuthResult.timeout() : const AuthResult.cancelled(),
        owner: completer,
      );
    }
  }

  /// Sign in directly with KRDPASS without a backend server (client-only mode).
  Future<KrdpassTokenResult> signIn({
    List<String> scopes = const [KrdpassScopes.openid, KrdpassScopes.profile],
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final platform = _requirePlatform;

    if (scopes.isEmpty) {
      throw ArgumentError.value(scopes, 'scopes', 'cannot be empty');
    }
    if (timeout.isNegative || timeout == Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }

    KrdpassLogger.info('Starting signIn');
    if (_isAuthenticating || _pendingCompleter != null) {
      throw const KrdpassBusyException();
    }

    _isAuthenticating = true;
    final Map<String, dynamic> resultMap;
    try {
      resultMap = await platform
          .signIn(scopes: scopes, timeout: timeout)
          .timeout(timeout);
    } on TimeoutException {
      await platform.cancelPending(timeout: true);
      throw const KrdpassTimeoutException();
    } on PlatformException catch (e) {
      await platform.cancelPending();
      throw _mapPlatformError(
        e,
        'Sign in failed',
        // platform.config, not the getter: dispose() may have run during the await.
        installUrl: platform.config.environment.installUrl,
      );
    } catch (e) {
      await platform.cancelPending();
      throw KrdpassAuthenticationException('Sign in failed', cause: e);
    } finally {
      _isAuthenticating = false;
    }

    // Parsed outside the try: the exchange has already succeeded, so a malformed
    // payload is a FormatException and must not cancel the flow (that would orphan
    // live credentials).
    return KrdpassTokenResult.fromJson(resultMap);
  }

  /// Fails closed: a returned state is only accepted when present and exactly
  /// matching; with no expected state the result is rejected (CSRF protection
  /// cannot be skipped).
  bool _isValidState(String? state) =>
      _expectedState != null && state != null && state == _expectedState;

  /// Get user information from CAS using an access token.
  Future<KrdpassUserInfo> getUserInfo({required String accessToken}) async {
    final platform = _requirePlatform;
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'cannot be empty');
    }

    final resultMap = await _runTokenOp(
      'Failed to get user info',
      () => platform.getUserInfo(accessToken: accessToken),
    );

    // The bridge sends camelCase keys; fromJson accepts both spellings.
    return KrdpassUserInfo.fromJson(resultMap);
  }

  Future<KrdpassTokenResult> refreshTokens({
    required String refreshToken,
    String? scope,
  }) async {
    final platform = _requirePlatform;
    if (refreshToken.isEmpty) {
      throw ArgumentError.value(
        refreshToken,
        'refreshToken',
        'cannot be empty',
      );
    }

    final resultMap = await _runTokenOp(
      'Failed to refresh tokens',
      () => platform.refreshTokens(refreshToken: refreshToken, scope: scope),
    );

    return KrdpassTokenResult.fromJson(resultMap);
  }

  Future<void> revokeToken({
    required String token,
    String? tokenTypeHint,
  }) async {
    final platform = _requirePlatform;
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'cannot be empty');
    }

    return _runTokenOp(
      'Failed to revoke token',
      () => platform.revokeToken(token: token, tokenTypeHint: tokenTypeHint),
    );
  }

  /// Decode a JWT payload into its claims **without verifying the signature**.
  ///
  /// SECURITY: the returned claims are not authenticated and must not drive any
  /// trust decision; call [verifyToken] first. Throws [FormatException] if
  /// [token] is not a parseable JWT.
  Map<String, dynamic> decodeTokenUnverified(String token) {
    if (token.isEmpty) {
      throw const FormatException('Token cannot be empty');
    }
    final parts = token.split('.');
    if (parts.length < 2) {
      throw const FormatException(
        'JWT must have at least a header and payload',
      );
    }

    try {
      final bytes = base64Decode(base64Url.normalize(parts[1]));
      final jsonString = utf8.decode(bytes);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      // Constant message: FormatException.toString() prints the offending source,
      // which would put decoded citizen claims into logs and crash telemetry.
      throw const FormatException('Not a valid JWT payload');
    }
  }

  /// Verify a JWT against the environment's JWKS and validate standard claims.
  ///
  /// The native cores pin `iss` to `environment.authServerUrl` and `aud` to the
  /// configured `clientId`, so no claim is left for the caller to compare.
  /// Throws [KrdpassTokenValidationException] with the native error as `cause`.
  Future<Map<String, dynamic>> verifyToken({
    required String idToken,
    Duration clockSkew = const Duration(seconds: 60),
  }) async {
    if (idToken.isEmpty) {
      throw ArgumentError.value(idToken, 'idToken', 'cannot be empty');
    }
    final platform = _requirePlatform;

    try {
      return await platform.verifyToken(token: idToken, clockSkew: clockSkew);
    } catch (e) {
      throw KrdpassTokenValidationException(e);
    }
  }

  void dispose() {
    _platform?.dispose();
    _platform = null;

    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(const AuthResult.cancelled());
    }
    _pendingCompleter = null;
    _expectedState = null;
    _isAuthenticating = false;
    _config = null;
  }

  /// Completes the pending flow with a result the native side pushed. Error
  /// redirects are state-validated too: an injected error carrying the wrong
  /// state is a response-injection attempt.
  void _completeFromWire(AuthResult result) {
    if ((result.isSuccess || result.state != null) &&
        !_isValidState(result.state)) {
      // Lengths only: the state is a CSRF secret, so no part of it is logged.
      KrdpassLogger.warning(
        'State mismatch: expected len=${_expectedState?.length ?? 0}, '
        'received len=${result.state?.length ?? 0}',
      );
      return _completeLocal(const AuthResult.stateMismatch());
    }
    _completeLocal(result);
  }

  /// Completes the pending flow with a locally built result; no state to validate. [owner] is the
  /// completer the caller captured before an await, so a continuation resuming after the app has
  /// started a new flow cannot settle that newer one. It guards the Dart-initiated paths only: a
  /// result pushed up from a native cancel carries no flow identity, so `_completeFromWire`
  /// settles whichever flow is current.
  void _completeLocal(AuthResult result, {Completer<AuthResult>? owner}) {
    final completer = _pendingCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (owner != null && !identical(owner, completer)) {
      return;
    }

    completer.complete(result);
    _pendingCompleter = null;
    _expectedState = null;
    _isAuthenticating = false;
  }

  AuthResult _settle(AuthResult result, {Completer<AuthResult>? owner}) {
    _completeLocal(result, owner: owner);
    return result;
  }
}

/// Base type for all errors thrown by the KRDPASS SDK's authentication flows.
///
/// [message] is always a user-safe canonical string, never a raw server body
/// or stack trace; raw detail stays in [cause].
sealed class KrdpassException implements Exception {
  const KrdpassException(this.message, {this.cause});

  /// A stable, user-safe description of the failure.
  final String message;

  /// The underlying error, if any (for logging/diagnostics, may contain detail).
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'KrdpassException: $message'
      : 'KrdpassException: $message ($cause)';
}

/// The user cancelled the authentication flow.
///
/// [cause] keeps the provider's own reason from the redirect, the one
/// diagnostic a cancelled flow has, while [message] stays canonical.
class KrdpassCancelledException extends KrdpassException {
  const KrdpassCancelledException({super.cause}) : super(kMsgCancelled);
}

/// The authentication flow timed out.
class KrdpassTimeoutException extends KrdpassException {
  const KrdpassTimeoutException() : super(kMsgTimeout);
}

/// Another authentication flow is already in progress.
class KrdpassBusyException extends KrdpassException {
  const KrdpassBusyException() : super(kMsgBusy);
}

/// A network or CAS communication error (PAR, token exchange, userinfo, refresh, revoke).
class KrdpassNetworkException extends KrdpassException {
  const KrdpassNetworkException(super.message, {super.cause});
}

/// Authentication failed (bad code, token exchange rejected, id_token invalid, etc.).
class KrdpassAuthenticationException extends KrdpassException {
  const KrdpassAuthenticationException(
    super.message, {
    this.code,
    this.installUrl,
    super.cause,
  });

  /// The native error code, if any (e.g. `provider_not_installed`), so callers
  /// can branch without parsing [message].
  final String? code;

  /// The KRDPASS install URL when [code] is `provider_not_installed`; null
  /// for other errors.
  final String? installUrl;
}

/// Runs a token-op channel call and maps its failures to the typed hierarchy.
Future<T> _runTokenOp<T>(
  String fallbackMessage,
  Future<T> Function() op,
) async {
  try {
    return await op();
  } on PlatformException catch (e) {
    throw _mapPlatformError(e, fallbackMessage);
  } catch (e) {
    // Only an identified transport failure gets network_error, which README documents
    // as safe to retry; anything else is deterministic and would loop forever.
    throw KrdpassAuthenticationException(fallbackMessage, cause: e);
  }
}

/// Maps a native [PlatformException] to the typed [KrdpassException] hierarchy,
/// preserving the native error code instead of collapsing it into a generic failure.
KrdpassException _mapPlatformError(
  PlatformException e,
  String fallbackMessage, {
  String? installUrl,
}) {
  // login_required/consent_denied count as cancellation too; see kCancelledCodes.
  if (kCancelledCodes.contains(e.code)) {
    return KrdpassCancelledException(cause: e);
  }
  switch (e.code) {
    case 'timeout':
      return const KrdpassTimeoutException();
    case 'busy':
      return const KrdpassBusyException();
    case 'network_error':
      // Keep the user-facing message canonical; the raw native detail stays in `cause`.
      return KrdpassNetworkException(fallbackMessage, cause: e);
    case 'issuer_mismatch':
      // RFC 9207 mix-up detection, kept separate so it is never reported as CSRF;
      // the canonical message wins over the bridge's possibly-blank text.
      return KrdpassAuthenticationException(
        kMsgIssuerMismatch,
        code: e.code,
        cause: e,
      );
    case 'nonce_mismatch':
      return KrdpassAuthenticationException(
        kMsgNonceMismatch,
        code: e.code,
        cause: e,
      );
    // invalid_request and invalid_id_token fall through on purpose: their native
    // text is the only diagnostic, and a canonical string would misreport it.
    default:
      final text = e.message;
      return KrdpassAuthenticationException(
        // Native text verbatim; blank counts as absent so an app displaying this
        // never renders "Failed: ".
        (text == null || text.isEmpty) ? fallbackMessage : text,
        code: e.code,
        installUrl: e.code == 'provider_not_installed' ? installUrl : null,
        cause: e,
      );
  }
}

/// ID token verification failed (bad signature, wrong issuer or audience,
/// expired, or the JWKS fetch failed). The native [PlatformException] stays
/// in [cause].
class KrdpassTokenValidationException extends KrdpassException {
  const KrdpassTokenValidationException(Object cause)
    : super('ID token verification failed', cause: cause);

  /// The native error code: `network_error` for a JWKS transport failure
  /// (retryable), `invalid_id_token`/`verification_failed` for a
  /// signature or claim failure (not retryable).
  String? get code =>
      cause is PlatformException ? (cause! as PlatformException).code : null;
}
