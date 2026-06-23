import 'dart:async';

import 'package:flutter/services.dart';

import '../models/auth_result.dart';
import 'krdpass_platform.dart';

/// iOS implementation of KrdpassAuth authentication.
///
/// iOS implementation of KRDPass authentication.
///
/// Uses the native iOS SDK via MethodChannel.
class IosKrdpassPlatform extends KrdpassPlatform {
  IosKrdpassPlatform({required super.config}) {
    _deepLinkController = StreamController<AuthResult>.broadcast();
    _channel.setMethodCallHandler(_handleMethodCall);
    _configure();
  }

  static const MethodChannel _channel = MethodChannel('krd.pass.krdpass_auth');

  StreamController<AuthResult>? _deepLinkController;
  void Function(AuthResult result)? _resultHandler;
  Completer<AuthResult>? _authCompleter;

  /// Stream of auth results from deep links.
  Stream<AuthResult> get deepLinkStream => _deepLinkController!.stream;

  Future<void> _configure() async {
    try {
      await _channel.invokeMethod('configure', {
        'clientId': config.clientId,
        'redirectUri': config.redirectUri,
        'environment': config.environment.name,
      });
    } catch (e) {
      throw Exception(
        'Failed to configure KRDPass iOS SDK. '
        'Original error: $e',
      );
    }
  }

  @override
  Future<bool> authenticate({required String requestUri, String? state}) async {
    try {
      _authCompleter = Completer<AuthResult>();
      await _configure();

      final arguments = <String, dynamic>{
        'requestUri': requestUri,
        if (state != null) 'state': state,
      };
      final result = await _channel.invokeMethod<bool>(
        'launchKRDPassForResult',
        arguments,
      );

      if (result != true) {
        _authCompleter?.completeError('Failed to launch KRDPass');
        _authCompleter = null;
      }
      return result ?? false;
    } catch (e) {
      _authCompleter?.completeError(e);
      _authCompleter = null;
      return false;
    }
  }

  @override
  Future<void> cancelPendingAuthentication({bool timeout = false}) async {
    try {
      await _channel.invokeMethod('cancelAuthentication', {'timeout': timeout});
    } catch (_) {
      // Best-effort; we'll still allow the Dart layer to stop waiting.
    }
  }

  @override
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    String? issuer,
    String? audience,
    Duration clockSkew = const Duration(seconds: 60),
  }) async {
    try {
      final arguments = <String, dynamic>{
        'token': token,
        if (issuer != null) 'issuer': issuer,
        if (audience != null) 'audience': audience,
        'clockSkew': clockSkew.inSeconds.toDouble(),
      };

      final result = await _channel.invokeMethod<Map>(
        'verifyToken',
        arguments,
      );

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
      // Wait for callback from iOS plugin (wraps delegate/callback)
      final completer = Completer<Map<String, dynamic>>();
      _pendingSignInCompleter = completer;

      await _channel.invokeMethod('signIn', {
        'scopes': scopes,
      });

      return completer.future;
    } on PlatformException catch (e) {
      _pendingSignInCompleter = null;
      throw Exception('Sign in failed: ${e.message}');
    }
  }

  Completer<Map<String, dynamic>>? _pendingSignInCompleter;

  @override
  Future<void> cancelPendingSignIn({bool timeout = false}) async {
    try {
      await _channel.invokeMethod('cancelAuthentication', {'timeout': timeout});
    } catch (_) {
      // Best-effort; we'll still clear local completer.
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
        if (scope != null) 'scope': scope,
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
        if (tokenTypeHint != null) 'tokenTypeHint': tokenTypeHint,
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

  void _completeWithResult(AuthResult result) {
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(result);
      _authCompleter = null;
    }

    _deepLinkController?.add(result);
    _resultHandler?.call(result);
  }

  /// Get the result of the authentication attempt.
  Future<AuthResult> get result =>
      _authCompleter?.future ?? Future.error('No authentication in progress');

  @override
  void setResultHandler(void Function(AuthResult result) handler) {
    _resultHandler = handler;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onAuthResult') {
      final args = call.arguments as Map;
      final code = args['code'] as String?;
      final error = args['error'] as String?;
      final errorDescription = args['error_description'] as String?;
      final state = args['state'] as String?;

      final result = _createAuthResult(code, state, error, errorDescription);
      _completeWithResult(result);
    } else if (call.method == 'onSignInResult') {
      final args = call.arguments as Map;
      if (args.containsKey('error')) {
        // Complete with a PlatformException carrying the native error code so the
        // client's `on PlatformException` arm runs _mapPlatformError and yields a
        // typed exception (cancelled/timeout/busy/...).
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
    if (code != null && error == null) {
      return AuthResult.success(code: code, state: state);
    } else if (error == 'cancelled' ||
        error == 'user_cancelled' ||
        error == 'access_denied' ||
        error == 'login_required' ||
        error == 'consent_denied') {
      return const AuthResult.cancelled();
    } else if (error == 'timeout') {
      return const AuthResult.timeout();
    } else if (error == 'busy') {
      return const AuthResult.busy();
    } else if (error != null) {
      return AuthResult.error(error: error, errorDescription: errorDescription);
    } else {
      return AuthResult.platformError(
        'Unknown result: code=$code, error=$error',
      );
    }
  }

  @override
  void dispose() {
    _resultHandler = null;
    _channel.setMethodCallHandler(null);
    _deepLinkController?.close();
    _deepLinkController = null;
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(const AuthResult.cancelled());
    }
    _authCompleter = null;
    if (_pendingSignInCompleter != null &&
        !_pendingSignInCompleter!.isCompleted) {
      _pendingSignInCompleter!.completeError(
        PlatformException(code: 'cancelled', message: 'Sign in cancelled'),
      );
    }
    _pendingSignInCompleter = null;
  }
}
