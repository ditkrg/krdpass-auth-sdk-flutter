import '../models/auth_result.dart';
import '../models/krdpass_config.dart';

/// Platform-specific interface for KRDPASS authentication.
abstract class KrdpassPlatform {
  KrdpassPlatform({required this.config});

  /// The configuration for this [KrdpassAuth] instance.
  final KrdpassConfig config;

  /// Launch KRDPASS app for authentication with the given request URI.
  Future<bool> authenticate({required String requestUri, String? state});

  /// Cancel any pending authentication flow on the platform side.
  ///
  /// This is a best-effort operation. Implementations should ensure any
  /// in-flight native authentication state is cleared so a new flow can start.
  Future<void> cancelPendingAuthentication({bool timeout = false});

  /// Verify a token using native SDK.
  Future<Map<String, dynamic>> verifyToken({
    required String token,
    Duration clockSkew = const Duration(seconds: 60),
  });

  /// Set a handler for auth results.
  void setResultHandler(void Function(AuthResult result) handler);

  /// Sign in directly using scopes (delegated to native SDK for logic).
  Future<Map<String, dynamic>> signIn({
    List<String> scopes = const ['openid', 'profile'],
  });

  /// Cancel any pending sign-in callback handlers on the platform side.
  ///
  /// If [timeout] is true, implementations should treat cancellation as a timeout.
  Future<void> cancelPendingSignIn({bool timeout = false});

  /// Refresh tokens using a refresh token.
  Future<Map<String, dynamic>> refreshTokens({
    required String refreshToken,
    String? scope,
  });

  /// Revoke a token.
  Future<void> revokeToken({required String token, String? tokenTypeHint});

  /// Get user info using an access token.
  Future<Map<String, dynamic>> getUserInfo({required String accessToken});

  /// Clean up resources.
  void dispose();
}
