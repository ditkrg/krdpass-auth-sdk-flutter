/// Sign in with KRDPASS.
///
/// Initialize once at startup with [KrdpassAuth.initialize]. Client-only flow:
/// [KrdpassAuth.signIn] runs PAR and the token exchange directly and returns
/// tokens. Backend-mediated flow: your server performs PAR and the token
/// exchange, [KrdpassAuth.authenticate] launches KRDPASS and returns the
/// authorization code; pass back the exact `state` your backend put in its
/// PAR request.
library;

export 'src/krdpass_auth.dart';
export 'src/logger.dart';
// kCancelledCodes is internal; tests reach it by its src/ path.
export 'src/models/auth_result.dart' hide kCancelledCodes;
export 'src/models/krdpass_config.dart';
export 'src/models/krdpass_environment.dart';
export 'src/models/krdpass_scopes.dart';
export 'src/models/krdpass_token_result.dart';
export 'src/models/krdpass_user_info.dart';
export 'src/pkce.dart';
