library;

/// Main library for Sign in with KRDPass.
///
/// Use [KrdpassAuth] for authentication:
/// ```dart
/// final auth = KrdpassAuth.instance;
/// await auth.initialize(config: config);
///
/// final pkce = auth.generatePkcePair();
/// final state = auth.generateState();
///
/// // requestUri is returned from your backend's /oauth/par endpoint.
/// await auth.authenticate(
///   requestUri: requestUri,
///   state: state,
/// );
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
