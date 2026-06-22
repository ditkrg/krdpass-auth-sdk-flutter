library;

/// Main library for Sign in with KRDPass.
///
/// Initialize once at startup:
/// ```dart
/// final auth = KrdpassAuth.instance;
/// await auth.initialize(
///   config: const KrdpassConfig(
///     clientId: 'your-client-id',
///     redirectUri: 'https://auth.your-app.example.com/callback',
///   ),
/// );
/// ```
///
/// Client-only flow ([KrdpassAuth.signIn]) — the SDK runs PAR and token
/// exchange directly with KRDPASS, returning tokens:
/// ```dart
/// final tokens = await auth.signIn(scopes: ['openid', 'profile']);
/// final userInfo = await auth.getUserInfo(accessToken: tokens.accessToken);
/// ```
///
/// Backend-mediated flow ([KrdpassAuth.authenticate]) — your server performs
/// PAR and the token exchange; the SDK only launches KRDPASS and returns the
/// authorization code:
/// ```dart
/// final state = auth.generateState();
/// // requestUri is returned from your backend's PAR endpoint.
/// final result = await auth.authenticate(requestUri: requestUri, state: state);
/// if (result.isSuccess) {
///   // Send result.code back to your backend to exchange for tokens.
/// }
/// ```

export 'src/krdpass_auth.dart';
export 'src/logger.dart';
export 'src/models/auth_result.dart';
export 'src/models/krdpass_config.dart';
export 'src/models/krdpass_environment.dart';
export 'src/models/krdpass_scopes.dart';
export 'src/models/krdpass_token_result.dart';
export 'src/models/krdpass_user_info.dart';
export 'src/pkce.dart';
