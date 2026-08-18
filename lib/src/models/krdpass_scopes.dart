/// Standard OAuth2 scopes supported by KRDPASS.
class KrdpassScopes {
  KrdpassScopes._();

  /// Required for OpenID Connect flows. Returns the 'sub' claim.
  static const String openid = 'openid';

  /// Returns standard profile claims (name, family_name, given_name, picture).
  static const String profile = 'profile';

  /// Returns digital identity claims (citizen_id, birthdate, etc.).
  static const String citizenIdentity = 'citizen_identity';

  /// Requests a refresh token for background/offline access.
  static const String offlineAccess = 'offline_access';
}
