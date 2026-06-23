import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'logger.dart';
import 'models/auth_result.dart';
import 'models/krdpass_config.dart';
import 'models/krdpass_token_result.dart';
import 'models/krdpass_user_info.dart';
import 'pkce.dart';
import 'platform/android_platform.dart';
import 'platform/ios_platform.dart';
import 'platform/krdpass_platform.dart';

/// Main SDK class for Sign in with KRDPass authentication.
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

  StreamSubscription<AuthResult>? _deepLinkSubscription;
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

  /// Initialize the SDK with the required configuration.
  ///
  /// This must be called once, typically at app startup.
  Future<void> initialize({
    required KrdpassConfig config,
  }) async {
    config.validate();
    _config = config;

    if (defaultTargetPlatform == TargetPlatform.android) {
      _platform = AndroidKrdpassPlatform(config: config);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      _platform = IosKrdpassPlatform(config: config);
      if (_platform case final IosKrdpassPlatform iosPlatform) {
        // Cancel existing subscription if re-initializing
        await _deepLinkSubscription?.cancel();
        _deepLinkSubscription = iosPlatform.deepLinkStream.listen((result) {
          if (_pendingCompleter != null && !result.isSuccess) {
            // Forward errors to pending auth
            _completeWithResult(result);
          }
        });
      }
    } else {
      throw UnsupportedError(
        'Platform $defaultTargetPlatform is not supported',
      );
    }

    _platform!.setResultHandler(_completeWithResult);
  }

  /// Generate a random state string for CSRF protection.
  ///
  /// This is an independent cryptographically-secure random token — NOT a PKCE
  /// code verifier — so `state` and the PKCE verifier never share a value.
  String generateState() => PkceGenerator.generateSecureToken();

  /// Generate a PKCE code verifier and challenge pair.
  PkcePair generatePkcePair() {
    return PkceGenerator.secure().generate();
  }

  /// Build the complete KRDPass authorization URL from a request URI.
  String buildAuthorizationUrl(String requestUri, [String? state]) {
    if (requestUri.isEmpty) {
      throw ArgumentError.value(requestUri, 'requestUri', 'cannot be empty');
    }
    final params = <String, String>{
      'client_id': config.clientId,
      'request_uri': requestUri,
      'redirect_uri': config.redirectUri,
    };
    if (state != null && state.isNotEmpty) params['state'] = state;
    final uri = Uri.parse(config.environment.authUrl).replace(
      queryParameters: params,
    );
    return uri.toString();
  }

  /// Launch KRDPass for authentication.
  Future<AuthResult> authenticate({
    required String requestUri,
    String? state,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Ensure initialized
    if (_config == null || _platform == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }

    if (requestUri.isEmpty) {
      return const AuthResult.platformError('requestUri cannot be empty');
    }
    if (timeout.isNegative || timeout == Duration.zero) {
      return const AuthResult.platformError('timeout must be positive');
    }
    // state is mandatory for CSRF / response-injection protection. Pass the state
    // your backend baked into the PAR request, or use signIn() which manages it.
    if (state == null || state.isEmpty) {
      return const AuthResult.platformError(
        'state is required and cannot be blank. Pass the state returned by your backend PAR call, or use signIn().',
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
      final launched = await _platform!.authenticate(
        requestUri: requestUri,
        state: state,
      );
      if (!launched) {
        const errorResult = AuthResult.error(
          error: 'launch_failed',
          errorDescription: 'Failed to launch KRDPass app.',
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
        await _platform!.cancelPendingAuthentication(timeout: true);
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

  /// Sign in directly with KRDPass without a backend server (client-only mode).
  Future<KrdpassTokenResult> signIn({
    List<String> scopes = const ['openid', 'profile'],
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Ensure initialized
    if (_config == null || _platform == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }

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
      final resultMap = await _platform!.signIn(scopes: scopes).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Sign in timed out');
        },
      );

      // Convert map to KrdpassTokenResult
      return KrdpassTokenResult(
        accessToken: resultMap['accessToken'] as String,
        idToken: resultMap['idToken'] as String?,
        tokenType: resultMap['tokenType'] as String,
        expiresIn: resultMap['expiresIn'] as int,
        refreshToken: resultMap['refreshToken'] as String?,
        scope: resultMap['scope'] as String?,
      );
    } on TimeoutException {
      await _platform!.cancelPendingSignIn(timeout: true);
      throw const KrdpassTimeoutException();
    } on KrdpassException {
      await _platform!.cancelPendingSignIn();
      rethrow;
    } on PlatformException catch (e) {
      await _platform!.cancelPendingSignIn();
      throw _mapPlatformError(e, 'Sign in failed');
    } catch (e) {
      await _platform!.cancelPendingSignIn();
      throw KrdpassAuthenticationException('Sign in failed', cause: e);
    } finally {
      _isAuthenticating = false;
    }
  }

  /// Convert an AuthResult to a CasException.
  CasException authResultToException(AuthResult result) {
    return CasException(result.errorMessage);
  }

  String _maskState(String? state) {
    if (state == null || state.isEmpty) return 'null';
    if (state.length <= 8) {
      return '${state.substring(0, 1)}…(len:${state.length})';
    }
    return '${state.substring(0, 4)}…${state.substring(state.length - 4)}(len:${state.length})';
  }

  /// Validate that a state parameter matches expected criteria.
  ///
  /// Fails closed: a returned state is only accepted when it is present and
  /// exactly matches the state we sent (or passes a configured validator).
  bool _isValidState(String? state) {
    // If we have an expected state, it must be present and match exactly.
    if (_expectedState != null) {
      return state != null && state == _expectedState;
    }
    // If no expected state but a validator is configured, defer to it.
    if (config.stateValidator != null) {
      return config.stateValidator!(state);
    }
    // No way to validate -> reject (CSRF protection cannot be skipped).
    return false;
  }

  /// Check if a URI is a valid redirect for this client.
  bool isValidRedirect(Uri uri) {
    return config.isValidRedirectUri(uri);
  }

  // MARK: - User Info

  /// Get user information from CAS using an access token.
  Future<KrdpassUserInfo> getUserInfo({required String accessToken}) async {
    // Ensure initialized
    if (_config == null || _platform == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'cannot be empty');
    }

    try {
      final resultMap = await _platform!.getUserInfo(accessToken: accessToken);

      // Convert map to KrdpassUserInfo
      return KrdpassUserInfo(
        sub: resultMap['sub'] as String,
        name: resultMap['name'] as String?,
        givenName: resultMap['givenName'] as String?,
        familyName: resultMap['familyName'] as String?,
        picture: resultMap['picture'] as String?,
        email: resultMap['email'] as String?,
        citizenFirst: resultMap['citizenFirst'] as String?,
        citizenSecond: resultMap['citizenSecond'] as String?,
        citizenThird: resultMap['citizenThird'] as String?,
        citizenSurname: resultMap['citizenSurname'] as String?,
        citizenProfilePicture: resultMap['citizenProfilePicture'] as String?,
        birthdate: resultMap['birthdate'] as String?,
        sexAtBirth: resultMap['sexAtBirth'] as String?,
        upn: resultMap['upn'] as String?,
        did: resultMap['did'] as String?,
        raw: resultMap['raw'] != null
            ? Map<String, dynamic>.from(resultMap['raw'] as Map)
            : {},
      );
    } catch (e) {
      throw KrdpassNetworkException('Failed to get user info', cause: e);
    }
  }

  /// Refresh tokens using a refresh token.
  Future<KrdpassTokenResult> refreshTokens({
    required String refreshToken,
    String? scope,
  }) async {
    // Ensure initialized
    if (_config == null || _platform == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }

    try {
      final resultMap = await _platform!.refreshTokens(
        refreshToken: refreshToken,
        scope: scope,
      );

      return KrdpassTokenResult(
        accessToken: resultMap['accessToken'] as String,
        idToken: resultMap['idToken'] as String?,
        tokenType: resultMap['tokenType'] as String,
        expiresIn: resultMap['expiresIn'] as int,
        refreshToken: resultMap['refreshToken'] as String?,
        scope: resultMap['scope'] as String?,
      );
    } catch (e) {
      throw KrdpassNetworkException('Failed to refresh tokens', cause: e);
    }
  }

  /// Revoke an access or refresh token.
  Future<void> revokeToken({
    required String token,
    String? tokenTypeHint,
  }) async {
    // Ensure initialized
    if (_config == null || _platform == null) {
      throw StateError(
        'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
      );
    }

    try {
      await _platform!.revokeToken(
        token: token,
        tokenTypeHint: tokenTypeHint,
      );
    } catch (e) {
      throw KrdpassNetworkException('Failed to revoke token', cause: e);
    }
  }

  // MARK: - Token Decoding

  /// Decode a JWT payload into its claims **without verifying the signature**.
  ///
  /// ⚠️ SECURITY: the returned claims are NOT authenticated and MUST NOT drive any
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
          'JWT must have at least a header and payload');
    }

    var base64 = parts[1];
    // Pad to multiple of 4
    final padding = base64.length % 4;
    if (padding > 0) {
      base64 = base64.padRight(base64.length + (4 - padding), '=');
    }

    // Convert URL-safe base64 to standard
    base64 = base64.replaceAll('-', '+').replaceAll('_', '/');

    try {
      final bytes = base64Decode(base64);
      final jsonString = utf8.decode(bytes);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Not a valid JWT payload: $e');
    }
  }

  /// Verify a JWT using the environment's JWKS endpoint and validate standard claims.
  /// Supports standard RSA/EC JWK keys provided by the issuer.
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    String? issuer,
    String? audience,
    Duration clockSkew = const Duration(seconds: 60),
  }) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'cannot be empty');
    }

    try {
      // Ensure initialized
      if (_config == null || _platform == null) {
        throw StateError(
          'KrdpassAuth not initialized. Call KrdpassAuth.instance.initialize() first.',
        );
      }

      return await _platform!.verifyToken(
        token: token,
        issuer: issuer,
        audience: audience,
        clockSkew: clockSkew,
      );
    } catch (e) {
      throw TokenValidationException([
        if (e is Exception) e else Exception(e.toString()),
      ]);
    }
  }

  /// Clean up resources used by this client.
  void dispose() {
    _deepLinkSubscription?.cancel();
    _deepLinkSubscription = null;
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
        errorDescription: 'State parameter does not match expected value',
      );
    }

    completer.complete(finalResult);
    _config?.onResult?.call(finalResult);
    _pendingCompleter = null;
    _expectedState = null;
    _isAuthenticating = false;
  }
}

/// Base type for all errors thrown by the KRDPass SDK's authentication flows.
///
/// Catch [KrdpassException] to handle any SDK error, or switch on the concrete
/// subtypes ([KrdpassCancelledException], [KrdpassTimeoutException],
/// [KrdpassBusyException], [KrdpassNetworkException],
/// [KrdpassAuthenticationException]) for specific handling. The user-facing
/// [message] never embeds raw platform/server text; any underlying error is kept
/// in [cause] for diagnostics.
sealed class KrdpassException implements Exception {
  const KrdpassException(this.message, {this.cause});

  /// A stable, user-safe description of the failure.
  final String message;

  /// The underlying error, if any (for logging/diagnostics — may contain detail).
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'KrdpassException: $message'
      : 'KrdpassException: $message ($cause)';
}

/// The user cancelled the authentication flow.
class KrdpassCancelledException extends KrdpassException {
  const KrdpassCancelledException() : super('Authentication was cancelled');
}

/// The authentication flow timed out.
class KrdpassTimeoutException extends KrdpassException {
  const KrdpassTimeoutException() : super('Authentication timed out');
}

/// Another authentication flow is already in progress.
class KrdpassBusyException extends KrdpassException {
  const KrdpassBusyException()
      : super('Another authentication flow is already in progress');
}

/// A network or CAS communication error (PAR, token exchange, userinfo, refresh, revoke).
class KrdpassNetworkException extends KrdpassException {
  const KrdpassNetworkException(super.message, {super.cause});
}

/// Authentication failed (bad code, token exchange rejected, id_token invalid, etc.).
class KrdpassAuthenticationException extends KrdpassException {
  const KrdpassAuthenticationException(super.message, {this.code, super.cause});

  /// The native error code, if any (e.g. `provider_not_installed`), so callers
  /// can branch without parsing [message].
  final String? code;
}

/// Maps a native [PlatformException] to the typed [KrdpassException] hierarchy,
/// preserving the native error code instead of collapsing it into a generic failure.
KrdpassException _mapPlatformError(PlatformException e, String fallbackMessage) {
  switch (e.code) {
    case 'cancelled':
    case 'user_cancelled':
    case 'access_denied':
      return const KrdpassCancelledException();
    case 'timeout':
      return const KrdpassTimeoutException();
    case 'busy':
      return const KrdpassBusyException();
    case 'network_error':
      return KrdpassNetworkException(e.message ?? fallbackMessage, cause: e);
    default:
      return KrdpassAuthenticationException(fallbackMessage, code: e.code, cause: e);
  }
}

/// Exception thrown when token verification fails.
class TokenValidationException implements Exception {
  TokenValidationException(this.errors);

  final Iterable<Exception> errors;

  @override
  String toString() =>
      'TokenValidationException: ${errors.map((e) => e.toString()).join(', ')}';
}

/// Exception thrown for CAS-related errors.
class CasException implements Exception {
  CasException(this.message);

  final String message;

  @override
  String toString() => 'CasException: $message';
}
