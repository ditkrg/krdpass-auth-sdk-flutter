import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'logger.dart';
import 'messages.dart';
import 'models/auth_result.dart';
import 'models/krdpass_config.dart';
import 'models/krdpass_token_result.dart';
import 'models/krdpass_user_info.dart';
import 'pkce.dart';
import 'platform/krdpass_platform.dart';
import 'platform/method_channel_krdpass_platform.dart';

/// Main SDK class for Sign in with KRDPASS authentication.
///
/// Uses the Singleton pattern. You must call [initialize] before using
/// [authenticate] or other methods.
class KrdpassAuth {
  // Private constructor
  KrdpassAuth._();
  // Singleton instance
  static final KrdpassAuth _instance = KrdpassAuth._();

  /// Access the shared instance of the SDK.
  static KrdpassAuth get instance => _instance;

  KrdpassConfig? _config;
  KrdpassPlatform? _platform;

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

  /// Returns the platform, asserting the SDK is initialized. Captures the non-null
  /// reference so it survives an `await` even if [dispose] nulls `_platform` mid-flight
  /// (a clean StateError up front instead of a later TypeError on a re-read `platform`).
  KrdpassPlatform get _requirePlatform {
    final platform = _platform;
    if (platform == null || _config == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }
    return platform;
  }

  /// Initialize the SDK with the required configuration.
  ///
  /// This must be called once, typically at app startup.
  Future<void> initialize({required KrdpassConfig config}) async {
    config.validate();
    _config = config;

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      _platform = MethodChannelKrdpassPlatform(config: config);
    } else {
      throw UnsupportedError(
        'Platform $defaultTargetPlatform is not supported',
      );
    }

    _platform!.setResultHandler(_completeWithResult);
  }

  /// Generate a random state string for CSRF protection.
  ///
  /// This is an independent cryptographically-secure random token, not a PKCE
  /// code verifier, so `state` and the PKCE verifier never share a value.
  String generateState() {
    final random = Random.secure();
    final bytes = List.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generate a PKCE code verifier and challenge pair.
  PkcePair generatePkcePair() {
    return PkceGenerator.secure().generate();
  }

  /// Launch KRDPASS for authentication.
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
    // state is mandatory for CSRF / response-injection protection. Pass the state
    // your backend baked into the PAR request, or use signIn() which manages it.
    if (state == null || state.isEmpty) {
      // invalid_request, not platform_error: same wire code as the Android/iOS cores for this
      // failure (and the code the provider itself uses for bad request params).
      return const AuthResult.error(
        error: 'invalid_request',
        errorDescription:
            "state is required and cannot be blank. Pass the state returned by your backend's PAR call, or use signIn().",
      );
    }

    if (_isAuthenticating || _pendingCompleter != null) {
      return const AuthResult.busy();
    }

    _isAuthenticating = true;
    _expectedState = state;
    KrdpassLogger.fine(
      'Auth state set: expected=${_maskState(_expectedState)}',
    );
    _pendingCompleter = Completer<AuthResult>();
    final completerFuture = _pendingCompleter!.future;

    try {
      final launched = await platform.authenticate(
        requestUri: requestUri,
        state: state,
      );
      if (!launched) {
        final errorResult = AuthResult.providerNotInstalled(
          installUrl: config.environment.installUrl,
        );
        _completeWithResult(errorResult);
        return errorResult;
      }

      // Wait for result with timeout
      return await completerFuture.timeout(timeout);
    } on TimeoutException {
      const timeoutResult = AuthResult.timeout();
      // Ensure native side is also cancelled/timed out so retries are not blocked by "busy".
      try {
        await platform.cancelPendingAuthentication(timeout: true);
      } catch (e) {
        KrdpassLogger.warning('Failed to timeout native auth flow: $e');
      }
      _completeWithResult(timeoutResult);
      return timeoutResult;
    } catch (e) {
      final errorResult = AuthResult.platformError(e.toString());
      _completeWithResult(errorResult);
      return errorResult;
    }
  }

  /// Cancel any in-flight authentication flow ([authenticate] or [signIn]).
  ///
  /// This is useful when your app returns to the foreground without receiving a
  /// redirect (e.g. the user app-switches back before completing the flow).
  ///
  /// By default, this completes the pending request as [AuthResult.cancelled].
  /// If [timeout] is true, it completes as [AuthResult.timeout] instead.
  Future<void> cancelPendingAuthentication({bool timeout = false}) async {
    final completer = _pendingCompleter;
    final hasPendingAuthenticate = completer != null && !completer.isCompleted;
    if (!_isAuthenticating && !hasPendingAuthenticate) return;

    try {
      await _platform?.cancelPendingAuthentication(timeout: timeout);
    } catch (e) {
      // Best-effort; still complete locally so callers can retry immediately.
      KrdpassLogger.warning('Failed to cancel native auth flow: $e');
    }

    if (hasPendingAuthenticate) {
      _completeWithResult(
        timeout ? const AuthResult.timeout() : const AuthResult.cancelled(),
      );
    }
  }

  /// Sign in directly with KRDPASS without a backend server (client-only mode).
  Future<KrdpassTokenResult> signIn({
    List<String> scopes = const ['openid', 'profile'],
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
    try {
      final resultMap = await platform
          .signIn(scopes: scopes)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('Sign in timed out');
            },
          );

      // Parse defensively: the native map crosses the method channel, where a JSON number
      // can arrive as int or double, so route it through fromJson rather than raw casts.
      return KrdpassTokenResult.fromJson(resultMap);
    } on TimeoutException {
      await platform.cancelPendingSignIn(timeout: true);
      throw const KrdpassTimeoutException();
    } on KrdpassException {
      await platform.cancelPendingSignIn();
      rethrow;
    } on PlatformException catch (e) {
      await platform.cancelPendingSignIn();
      throw _mapPlatformError(
        e,
        'Sign in failed',
        installUrl: config.environment.installUrl,
      );
    } catch (e) {
      await platform.cancelPendingSignIn();
      throw KrdpassAuthenticationException('Sign in failed', cause: e);
    } finally {
      _isAuthenticating = false;
    }
  }

  String _maskState(String? state) {
    if (state == null || state.isEmpty) return 'null';
    if (state.length <= 8) {
      return '${state.substring(0, 1)}...(len:${state.length})';
    }
    return '${state.substring(0, 4)}...${state.substring(state.length - 4)}(len:${state.length})';
  }

  /// Validate that a state parameter matches expected criteria.
  ///
  /// Fails closed: a returned state is only accepted when it is present and
  /// exactly matches the state we sent. With no expected state there is no way
  /// to validate, so the result is rejected (CSRF protection cannot be skipped).
  bool _isValidState(String? state) =>
      _expectedState != null && state != null && state == _expectedState;

  // MARK: - User Info

  /// Get user information from CAS using an access token.
  Future<KrdpassUserInfo> getUserInfo({required String accessToken}) async {
    final platform = _requirePlatform;
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'cannot be empty');
    }

    try {
      final resultMap = await platform.getUserInfo(accessToken: accessToken);

      // The native getUserInfo bridge returns camelCase keys (e.g. givenName), unlike the
      // snake_case OIDC server response. fromJson accepts both.
      return KrdpassUserInfo.fromJson(resultMap);
    } catch (e) {
      throw KrdpassNetworkException('Failed to get user info', cause: e);
    }
  }

  /// Refresh tokens using a refresh token.
  Future<KrdpassTokenResult> refreshTokens({
    required String refreshToken,
    String? scope,
  }) async {
    final platform = _requirePlatform;

    try {
      final resultMap = await platform.refreshTokens(
        refreshToken: refreshToken,
        scope: scope,
      );

      // Parse defensively (int/double + snake_case) instead of raw casts on channel data.
      return KrdpassTokenResult.fromJson(resultMap);
    } catch (e) {
      throw KrdpassNetworkException('Failed to refresh tokens', cause: e);
    }
  }

  /// Revoke an access or refresh token.
  Future<void> revokeToken({
    required String token,
    String? tokenTypeHint,
  }) async {
    final platform = _requirePlatform;

    try {
      await platform.revokeToken(token: token, tokenTypeHint: tokenTypeHint);
    } catch (e) {
      throw KrdpassNetworkException('Failed to revoke token', cause: e);
    }
  }

  // MARK: - Token Decoding

  /// Decode a JWT payload into its claims **without verifying the signature**.
  ///
  /// SECURITY: the returned claims are NOT authenticated and MUST NOT drive any
  /// trust or authorization decision. Always call [verifyToken] first; this is only
  /// for cosmetic display of an already-verified token.
  ///
  /// Throws [FormatException] if [token] is not a parseable JWT.
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
    } catch (e) {
      throw FormatException('Not a valid JWT payload: $e');
    }
  }

  /// Verify a JWT using the environment's JWKS endpoint and validate standard claims.
  ///
  /// The audience is derived automatically from the configured `clientId` (matching
  /// the Android/React Native SDKs). This convenience verifier validates the RS256
  /// signature, audience, and expiry; the security-critical [signIn] trust path
  /// additionally pins the issuer and binds the nonce.
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
      throw TokenValidationException(e);
    }
  }

  /// Clean up resources used by this client.
  void dispose() {
    _platform?.dispose();
    _platform = null;

    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(const AuthResult.cancelled());
    }
    _pendingCompleter = null;
    _expectedState = null;
    _isAuthenticating = false;
    _config = null; // Reset config on dispose
  }

  void _completeWithResult(AuthResult result) {
    final completer = _pendingCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    var finalResult = result;
    // Validate state if we have a successful result with state
    if (result.isSuccess && !_isValidState(result.state)) {
      KrdpassLogger.warning(
        'State mismatch: expected=${_maskState(_expectedState)} received=${_maskState(result.state)}',
      );
      finalResult = const AuthResult.stateMismatch(
        errorDescription:
            'State parameter mismatch: possible CSRF or response injection',
      );
    }

    completer.complete(finalResult);
    _pendingCompleter = null;
    _expectedState = null;
    _isAuthenticating = false;
  }
}

/// Base type for all errors thrown by the KRDPASS SDK's authentication flows.
///
/// Catch [KrdpassException] to handle any SDK error, or switch on the concrete
/// subtypes ([KrdpassCancelledException], [KrdpassTimeoutException],
/// [KrdpassBusyException], [KrdpassNetworkException],
/// [KrdpassAuthenticationException]) for specific handling. [message] is always a
/// user-safe canonical string (never a raw server body or stack trace): the
/// cancelled/timeout/busy/network messages are this SDK's own constants, while
/// [KrdpassAuthenticationException] carries the native SDK's canonical signIn-flow
/// message, the cross-platform source of truth. Raw detail stays in [cause].
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
class KrdpassCancelledException extends KrdpassException {
  const KrdpassCancelledException() : super(kMsgCancelled);
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

  /// The KRDPASS install URL when [code] is `provider_not_installed`. Open in a
  /// browser to take the user to the app store install page. Null for other errors.
  final String? installUrl;
}

/// Maps a native [PlatformException] to the typed [KrdpassException] hierarchy,
/// preserving the native error code instead of collapsing it into a generic failure.
KrdpassException _mapPlatformError(
  PlatformException e,
  String fallbackMessage, {
  String? installUrl,
}) {
  // login_required/consent_denied count as cancellation too. See kCancelledCodes,
  // shared with the authenticate-path result mapping so the two can't diverge.
  if (kCancelledCodes.contains(e.code)) {
    return const KrdpassCancelledException();
  }
  switch (e.code) {
    case 'timeout':
      return const KrdpassTimeoutException();
    case 'busy':
      return const KrdpassBusyException();
    case 'network_error':
      // Keep the user-facing message canonical; the raw native detail stays in `cause`.
      return KrdpassNetworkException(fallbackMessage, cause: e);
    default:
      return KrdpassAuthenticationException(
        // Surface the native SDK's canonical signIn-flow message (e.g. "No authorization
        // code received", "ID token nonce mismatch (possible token replay)") so the displayed
        // text matches Android/iOS/RN, since the native side is the source of truth for these.
        e.message ?? fallbackMessage,
        code: e.code,
        // installUrl is derived from local config; only meaningful for provider_not_installed.
        installUrl: e.code == 'provider_not_installed' ? installUrl : null,
        cause: e,
      );
  }
}

/// Exception thrown when token verification fails.
class TokenValidationException implements Exception {
  TokenValidationException(this.cause);

  final Object cause;

  @override
  String toString() => 'TokenValidationException: $cause';
}

/// Exception thrown for CAS-related errors.
class CasException implements Exception {
  CasException(this.message);

  final String message;

  @override
  String toString() => 'CasException: $message';
}
