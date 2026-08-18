import 'dart:async';

import 'package:flutter/services.dart';

import '../models/auth_result.dart';
import '../models/krdpass_config.dart';

/// `MethodChannel` bridge to the native cores, shared by Android and iOS.
class MethodChannelKrdpassPlatform {
  MethodChannelKrdpassPlatform({required this.config}) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('krd.pass.krdpass_auth');

  final KrdpassConfig config;

  /// Called with every authorization-code result the native side pushes.
  void Function(AuthResult result)? resultHandler;
  Completer<Map<String, dynamic>>? _pendingSignInCompleter;

  Future<void>? _configureAttempt;

  /// Sends `configure` to the native side, at most once per bridge instance:
  /// both bridges answer `invalid_request` until it has run, and re-sending is
  /// not free (iOS allocates a fresh core, Android clears its JWKS cache).
  /// Only success is remembered; a failed attempt is retried by the next call.
  Future<void> _configure() async {
    final attempt = _configureAttempt;
    if (attempt != null) return attempt;

    // Not wrapped: the native PlatformException keeps its code and message for
    // the caller to map like any other channel failure.
    final pending = _channel.invokeMethod<void>('configure', {
      'clientId': config.clientId,
      'redirectUri': config.redirectUri,
      'environment': config.environment.name,
    });
    _configureAttempt = pending;
    try {
      await pending;
    } catch (_) {
      _configureAttempt = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _callMap(
    String method,
    Map<String, Object?> args,
  ) async {
    await _configure();
    final result = await _channel.invokeMethod<Map>(method, args);
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Launches KRDPASS. The outcome, including `provider_not_installed`,
  /// arrives later via 'onAuthResult'; a configure failure escapes as a
  /// [PlatformException].
  Future<void> authenticate({
    required String requestUri,
    required Duration timeout,
    String? state,
  }) async {
    await _configure();
    await _channel.invokeMethod<void>('launchKRDPassForResult', {
      'requestUri': requestUri,
      'state': ?state,
      'timeoutMillis': timeout.inMilliseconds,
    });
  }

  /// Cancels any in-flight native flow, then settles a pending [signIn] locally.
  ///
  /// The local settle is a backstop: the Android core drops a cancel issued during
  /// the PAR window (before the flow claims the in-flight slot), which would
  /// otherwise leave the caller awaiting a callback that never fires.
  Future<void> cancelPending({bool timeout = false}) async {
    try {
      await _channel.invokeMethod('cancelAuthentication', {'timeout': timeout});
    } catch (_) {
      // Best-effort; the Dart layer stops waiting regardless.
    }
    _settlePendingSignIn(timeout ? 'timeout' : 'cancelled');
  }

  /// Verifies a token natively. PlatformException is not caught here: it
  /// carries the native error code, which [KrdpassAuth.verifyToken] keeps as
  /// the `cause` of the exception it throws.
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    Duration clockSkew = const Duration(seconds: 60),
  }) => _callMap('verifyToken', {
    'token': token,
    'clockSkew': clockSkew.inSeconds,
  });

  Future<Map<String, dynamic>> signIn({
    required List<String> scopes,
    required Duration timeout,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    try {
      await _configure();
      // Defence only: KrdpassAuth gates concurrent sign-ins, and this bridge is not exported,
      // so a live strand cannot reach here.
      _settlePendingSignIn('cancelled');
      _pendingSignInCompleter = completer;
      // The native side acks immediately; the outcome arrives via 'onSignInResult'.
      await _channel.invokeMethod('signIn', {
        'scopes': scopes,
        'timeoutMillis': timeout.inMilliseconds,
      });
    } on PlatformException {
      _pendingSignInCompleter = null;
      rethrow;
    }
    return completer.future;
  }

  Future<Map<String, dynamic>> refreshTokens({
    required String refreshToken,
    String? scope,
  }) => _callMap('refreshTokens', {
    'refreshToken': refreshToken,
    'scope': ?scope,
  });

  Future<void> revokeToken({
    required String token,
    String? tokenTypeHint,
  }) async {
    await _configure();
    await _channel.invokeMethod('revokeToken', {
      'token': token,
      'tokenTypeHint': ?tokenTypeHint,
    });
  }

  Future<Map<String, dynamic>> getUserInfo({required String accessToken}) =>
      _callMap('getUserInfo', {'accessToken': accessToken});

  /// Detaches the bridge, cancelling any native flow first: without that an in-flight Android
  /// flow holds the core's process-wide slot and the next `authenticate` is turned away as busy
  /// until its old timeout elapses. Both cores no-op the cancel when nothing is pending; when
  /// something is, the result lands on whichever bridge next attaches to this channel.
  void dispose() {
    _channel
        .invokeMethod<void>('cancelAuthentication', {'timeout': false})
        .catchError((Object _) {});
    resultHandler = null;
    _channel.setMethodCallHandler(null);
    _settlePendingSignIn('cancelled');
  }

  /// Completes any pending sign-in with [code] so its caller stops waiting;
  /// the code goes through the same taxonomy as a native one.
  void _settlePendingSignIn(String code) {
    final completer = _pendingSignInCompleter;
    _pendingSignInCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(PlatformException(code: code));
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAuthResult':
        final args = call.arguments as Map;
        resultHandler?.call(
          createAuthResult(
            code: args['code'] as String?,
            state: args['state'] as String?,
            error: args['error'] as String?,
            errorDescription: args['error_description'] as String?,
          ),
        );
      case 'onSignInResult':
        final args = call.arguments as Map;
        if (args.containsKey('error')) {
          _pendingSignInCompleter?.completeError(
            PlatformException(
              code: (args['error'] as String?) ?? 'authentication_failed',
              message: args['error_description'] as String?,
            ),
          );
        } else {
          _pendingSignInCompleter?.complete(Map<String, dynamic>.from(args));
        }
        _pendingSignInCompleter = null;
    }
  }

  /// The single result mapping, for `onAuthResult` and for synchronous
  /// `invokeMethod` failures, so both routes keep the documented wire codes.
  AuthResult createAuthResult({
    String? code,
    String? state,
    String? error,
    String? errorDescription,
  }) {
    // State validation is handled at the client level.
    if (code != null && error == null) {
      return AuthResult.success(code: code, state: state);
    }
    if (kCancelledCodes.contains(error)) {
      // The provider's own reason survives, only the code is canonicalized.
      return AuthResult.cancelled(
        errorDescription: errorDescription,
        state: state,
      );
    }
    switch (error) {
      case 'timeout':
        return const AuthResult.timeout();
      case 'busy':
        return const AuthResult.busy();
      case 'provider_not_installed':
        // installUrl comes from local config, not the channel.
        return AuthResult.providerNotInstalled(
          installUrl: config.environment.installUrl,
        );
    }
    if (error != null) {
      return AuthResult.error(
        error: error,
        errorDescription: errorDescription,
        state: state,
      );
    }
    // Only reachable when code and error are both null.
    return const AuthResult.platformError(
      'Result carried no code and no error',
    );
  }
}
