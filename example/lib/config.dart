import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String _requireEnv(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing required env var: $key');
    }
    return value;
  }

  // Required configuration from .env
  static String get clientId => _requireEnv('CLIENT_ID');

  static String get redirectUri => _requireEnv('REDIRECT_URI');

  static String get backendUrl => _requireEnv('BACKEND_URL');

  static String get parEndpoint => '$backendUrl/oauth/par';
  static String get tokenEndpoint => '$backendUrl/oauth/token';

  // For client-only testing - direct CAS URLs
  static String get casAuthServerUrl => _requireEnv('CAS_AUTH_SERVER_URL');
  static String get casTokenUrl => _requireEnv('CAS_TOKEN_URL');
  static String get casParUrl => _requireEnv('CAS_PAR_URL');
}
