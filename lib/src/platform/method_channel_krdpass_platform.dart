import 'dart:async';

import 'package:flutter/services.dart';

import '../models/auth_result.dart';
import 'krdpass_platform.dart';

/// `MethodChannel` implementation shared by Android and iOS.
///
/// Both platforms speak the same channel contract, so the channel calls,
/// in-flight sign-in completer, and result mapping live here once.
class MethodChannelKrdpassPlatform extends KrdpassPlatform {
  MethodChannelKrdpassPlatform({required super.config}) {
    _channel.setMethodCallHandler(_handleMethodCall);
    // Eager warm-up only: every flow re-runs `await _configure()` with proper error
    // propagation, so a failure here must not surface as an unhandled async zone error.
    unawaited(_configure().then((_) {}, onError: (Object _) {}));
  }

  static const MethodChannel _channel = MethodChannel('krd.pass.krdpass_auth');

  void Function(AuthResult result)? _resultHandler;
  Completer<Map<String, dynamic>>? _pendingSignInCompleter;

  Future<void> _configure() async {
    try {
      await _channel.invokeMethod('configure', {
        'clientId': config.clientId,
        'redirectUri': config.redirectUri,
        'environment': config.environment.name,
      });
    } catch (e) {
      throw Exception(
        'Failed to configure the KRDPASS native SDK. Original error: $e',
      );
    }
  }

  @override
  Future<bool> authenticate({required String requestUri, String? state}) async {
    try {
      // Re-configure in case the config changed or the process was restored.
      await _configure();
      final launched = await _channel.invokeMethod<bool>(
        'launchKRDPassForResult',
        {'requestUri': requestUri, 'state': ?state},
      );
      // The caller (KrdpassAuth.authenticate) maps a false return to
      // provider_not_installed; the real outcome arrives via 'onAuthResult'.
      return launched ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancelPendingAuthentication({bool timeout = false}) async {
    try {
      await _channel.invokeMethod('cancelAuthentication', {'timeout': timeout});
    } catch (_) {
      // Best-effort; the Dart layer stops waiting regardless.
    }
  }

  @override
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    Duration clockSkew = const Duration(seconds: 60),
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('verifyToken', {
        'token': token,
        'clockSkew': clockSkew.inSeconds,
      });
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      throw Exception('Token verification failed: ${e.message}');
    }
  }

  @override
  Future<Map<String, dynamic>> signIn({
    List<String> scopes = const ['openid', 'profile'],
  }) async {
    try {
      await _configure();
      final completer = Completer<Map<String, dynamic>>();
      _pendingSignInCompleter = completer;
      // The native side acks this invoke immediately; the real outcome arrives
      // later via the 'onSignInResult' callback into the completer.
      await _channel.invokeMethod('signIn', {'scopes': scopes});
      return completer.future;
    } on PlatformException catch (e) {
      _pendingSignInCompleter = null;
      throw Exception('Sign in failed: ${e.message}');
    }
  }

  @override
  Future<void> cancelPendingSignIn({bool timeout = false}) async {
    try {
      await _channel.invokeMethod('cancelAuthentication', {'timeout': timeout});
    } catch (_) {
      // Best-effort; clear the local completer regardless.
    }
    _pendingSignInCompleter = null;
  }

  @override
  Future<Map<String, dynamic>> refreshTokens({
    required String refreshToken,
    String? scope,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('refreshTokens', {
        'refreshToken': refreshToken,
        'scope': ?scope,
      });
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      throw Exception('Refresh failed: ${e.message}');
    }
  }

  @override
  Future<void> revokeToken({
    required String token,
    String? tokenTypeHint,
  }) async {
    try {
      await _channel.invokeMethod('revokeToken', {
        'token': token,
        'tokenTypeHint': ?tokenTypeHint,
      });
    } on PlatformException catch (e) {
      throw Exception('Revoke failed: ${e.message}');
    }
  }

  @override
  Future<Map<String, dynamic>> getUserInfo({
    required String accessToken,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('getUserInfo', {
        'accessToken': accessToken,
      });
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      throw Exception('GetUserInfo failed: ${e.message}');
    }
  }

  @override
  void setResultHandler(void Function(AuthResult result) handler) {
    _resultHandler = handler;
  }

  @override
  void dispose() {
    _resultHandler = null;
    _channel.setMethodCallHandler(null);
    if (_pendingSignInCompleter != null &&
        !_pendingSignInCompleter!.isCompleted) {
      _pendingSignInCompleter!.completeError(
        PlatformException(code: 'cancelled', message: 'Sign in cancelled'),
      );
    }
    _pendingSignInCompleter = null;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAuthResult':
        final args = call.arguments as Map;
        _resultHandler?.call(
          _createAuthResult(
            args['code'] as String?,
            args['state'] as String?,
            args['error'] as String?,
            args['error_description'] as String?,
          ),
        );
      case 'onSignInResult':
        final args = call.arguments as Map;
        if (args.containsKey('error')) {
          // Carry the native error code so the client's `on PlatformException`
          // arm maps it to a typed exception (cancelled/timeout/busy/...).
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

  AuthResult _createAuthResult(
    String? code,
    String? state,
    String? error,
    String? errorDescription,
  ) {
    // State validation is handled at the client level.
    if (code != null && error == null) {
      return AuthResult.success(code: code, state: state);
    }
    if (kCancelledCodes.contains(error)) {
      return const AuthResult.cancelled();
    }
    switch (error) {
      case 'timeout':
        return const AuthResult.timeout();
      case 'busy':
        return const AuthResult.busy();
      case 'provider_not_installed':
        // installUrl is derived from the environment we already hold, no need
        // to ferry it across the method channel.
        return AuthResult.providerNotInstalled(
          installUrl: config.environment.installUrl,
        );
    }
    if (error != null) {
      return AuthResult.error(error: error, errorDescription: errorDescription);
    }
    return AuthResult.platformError('Unknown result: code=$code, error=$error');
  }
}
