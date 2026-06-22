import 'dart:convert';

import 'package:demo_krdpass_auth/config.dart';
import 'package:http/http.dart' as http;
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

class ParResponse {
  final String requestUri;
  final int? expiresIn;
  final String? state;

  ParResponse({required this.requestUri, this.expiresIn, this.state});

  factory ParResponse.fromJson(Map<String, dynamic> json) {
    return ParResponse(
      requestUri: json['requestUri'] as String,
      expiresIn: json['expiresIn'] as int?,
      state: json['state'] as String?,
    );
  }
}

class AuthBackendService {
  static String normalizeEnvironment(String environment) {
    final normalized = environment.trim().toLowerCase();
    if (normalized == 'production' || normalized == 'prod') return 'production';
    if (normalized == 'development' || normalized == 'dev') {
      return 'development';
    }
    throw ArgumentError.value(
      environment,
      'environment',
      'must be one of: production, development',
    );
  }

  static Future<ParResponse> getRequestUri({
    required String codeChallenge,
    String? state,
    String? nonce,
    required String environment,
    required String redirectUri,
    String? scope,
  }) async {
    final normalizedEnvironment = normalizeEnvironment(environment);
    final requestBody = {
      'codeChallenge': codeChallenge,
      'codeChallengeMethod': 'S256',
      'environment': normalizedEnvironment,
      'redirectUri': redirectUri,
      'state': ?state,
      'nonce': ?nonce,
      'scope': ?scope,
    };

    final response = await http.post(
      Uri.parse(Config.parEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'PAR request failed: ${response.statusCode}\n${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception('PAR request failed: ${data['error']}');
    }

    final parResponse = ParResponse.fromJson(data);
    return parResponse;
  }

  static Future<KrdpassTokenResult> exchangeToken({
    required String code,
    required String state,
    required String codeVerifier,
    required String environment,
    required String redirectUri,
  }) async {
    final normalizedEnvironment = normalizeEnvironment(environment);
    final response = await http.post(
      Uri.parse(Config.tokenEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'state': state,
        'codeVerifier': codeVerifier,
        'environment': normalizedEnvironment,
        'redirectUri': redirectUri,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Token exchange failed: ${response.statusCode}');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    return KrdpassTokenResult.fromJson(tokenData);
  }

  static Future<KrdpassTokenResult> refreshToken({
    required String refreshToken,
    required String environment,
    String? scope,
  }) async {
    final normalizedEnvironment = normalizeEnvironment(environment);
    final body = {
      'refreshToken': refreshToken,
      'environment': normalizedEnvironment,
      'scope': ?scope,
    };

    final response = await http.post(
      Uri.parse('${Config.backendUrl}/oauth/token/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Refresh failed: ${response.statusCode}');
    }

    final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
    return KrdpassTokenResult.fromJson(tokenData);
  }

  static Future<void> revokeToken({
    required String token,
    required String environment,
    String tokenTypeHint = 'access_token',
  }) async {
    final normalizedEnvironment = normalizeEnvironment(environment);
    final body = {
      'token': token,
      'environment': normalizedEnvironment,
      'tokenTypeHint': tokenTypeHint,
    };

    final response = await http.post(
      Uri.parse('${Config.backendUrl}/oauth/token/revoke'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Revoke failed: ${response.statusCode}');
    }
  }
}
