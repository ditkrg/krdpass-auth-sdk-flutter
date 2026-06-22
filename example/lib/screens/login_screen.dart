import 'package:demo_krdpass_auth/config.dart';
import 'package:demo_krdpass_auth/services/auth_backend_service.dart';
import 'package:demo_krdpass_auth/widgets/authenticated_view.dart';
import 'package:demo_krdpass_auth/widgets/login_view.dart';
import 'package:flutter/material.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

class _AuthResult {
  final String accessToken;
  final String? idToken;
  final String? refreshToken;

  const _AuthResult(this.accessToken, this.idToken, this.refreshToken);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- Auth State ---
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _authToken;
  String? _idToken;
  String? _refreshToken;
  String? _error;
  String? _actionMessage; // New state for inline status

  // --- UI/Config State ---
  KrdpassUserInfo? _userInfo;
  bool _isLoadingUserInfo = false;
  bool _includeCitizenScope = true;
  bool _includeOfflineScope = true;
  bool _useServerMode = true;

  @override
  void initState() {
    super.initState();
    // KrdpassAuth is initialized in main.dart
  }

  @override
  void dispose() {
    // No need to dispose singleton
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoggedIn
              ? AuthenticatedView(
                  authToken: _authToken,
                  idToken: _idToken,
                  userInfo: _userInfo,
                  isLoadingUserInfo: _isLoadingUserInfo,
                  onFetchUserInfo: _handleFetchUserInfo,
                  onLogout: _handleLogout,
                  onVerifyToken: () => _handleVerifyToken(),
                  onRefreshToken: _handleRefreshToken,
                  onRevokeToken: _handleRevokeToken,
                  actionMessage: _actionMessage,
                )
              : LandingScreen(
                  loading: _isLoading,
                  error: _error,
                  citizenScope: _includeCitizenScope,
                  offlineScope: _includeOfflineScope,
                  useServerMode: _useServerMode,
                  onCitizenScopeChange: (val) =>
                      setState(() => _includeCitizenScope = val),
                  onOfflineScopeChange: (val) =>
                      setState(() => _includeOfflineScope = val),
                  onServerModeChange: (val) =>
                      setState(() => _useServerMode = val),
                  onSignInClick: () => _handleSignIn(_useServerMode),
                  onClearError: () => setState(() => _error = null),
                ),
        ),
      ),
    );
  }

  // MARK: - SDK Integration (Core Auth Logic)

  Future<void> _handleSignIn(bool useServerMode) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final authResult = await (useServerMode
          ? _loginServerMode()
          : _loginClientMode());
      _authToken = authResult.accessToken;
      _idToken = authResult.idToken;
      _refreshToken = authResult.refreshToken;
      setState(() => _isLoggedIn = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFetchUserInfo() async {
    if (_authToken == null) return;
    setState(() => _isLoadingUserInfo = true);
    try {
      final info = await KrdpassAuth.instance.getUserInfo(
        accessToken: _authToken!,
      );
      setState(() => _userInfo = info);
      _showStatus('✅ User Info Synced');
    } catch (e) {
      _showStatus('❌ Sync Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingUserInfo = false);
    }
  }

  Future<void> _handleRefreshToken() async {
    if (_refreshToken == null) {
      _showStatus('❌ No Refresh Token available');
      return;
    }
    setState(() => _isLoading = true);
    try {
      KrdpassTokenResult newTokens;
      if (_useServerMode) {
        newTokens = await AuthBackendService.refreshToken(
          refreshToken: _refreshToken!,
          environment: KrdpassAuth.instance.config.environment.name,
        );
      } else {
        final result = await KrdpassAuth.instance.refreshTokens(
          refreshToken: _refreshToken!,
        );
        newTokens = result;
      }
      setState(() {
        _authToken = newTokens.accessToken;
        _idToken = newTokens.idToken;
        _refreshToken = newTokens.refreshToken;
      });
      _showStatus('✅ Tokens Refreshed');
    } catch (e) {
      _showStatus('❌ Refresh Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRevokeToken() async {
    if (_authToken == null) {
      _showStatus('❌ No Access Token to revoke');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_useServerMode) {
        await AuthBackendService.revokeToken(
          token: _authToken!,
          environment: KrdpassAuth.instance.config.environment.name,
        );
      } else {
        await KrdpassAuth.instance.revokeToken(token: _authToken!);
      }
      _handleLogout();
      _showStatus('✅ Token Revoked (Logged Out)');
    } catch (e) {
      _showStatus('❌ Revoke Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyToken() async {
    if (_idToken == null) {
      _showStatus('❌ No ID Token to verify');
      return;
    }
    try {
      final claims = await KrdpassAuth.instance.verifyToken(token: _idToken!);
      final sub = claims['sub'];
      final suffix = sub is String && sub.isNotEmpty ? ' (sub: $sub)' : '';
      _showStatus('✅ Token Signature Valid$suffix');
    } catch (e) {
      _showStatus('❌ Invalid: $e');
    }
  }

  void _handleLogout() => setState(() {
    _isLoggedIn = false;
    _authToken = null;
    _idToken = null;
    _refreshToken = null;
    _error = null;
    _userInfo = null;
    _isLoadingUserInfo = false;
    _actionMessage = null; // Reset status on logout
  });

  void _showStatus(String message) {
    if (!mounted) return;
    setState(() => _actionMessage = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _actionMessage == message) {
        setState(() => _actionMessage = null);
      }
    });
  }

  // MARK: - Internal Auth Flow Details

  Future<_AuthResult> _loginServerMode() async {
    final pkce = KrdpassAuth.instance.generatePkcePair();
    final state = KrdpassAuth.instance.generateState();
    final nonce = KrdpassAuth.instance.generateState();
    final scopes = [KrdpassScopes.openid, KrdpassScopes.profile];
    if (_includeCitizenScope) scopes.add(KrdpassScopes.citizenIdentity);
    if (_includeOfflineScope) scopes.add(KrdpassScopes.offlineAccess);

    final parResponse = await AuthBackendService.getRequestUri(
      codeChallenge: pkce.codeChallenge,
      state: state,
      nonce: nonce,
      environment: KrdpassAuth.instance.config.environment.name,
      redirectUri: Config.redirectUri,
      scope: scopes.join(' '),
    );

    final result = await KrdpassAuth.instance.authenticate(
      requestUri: parResponse.requestUri,
      state: parResponse.state,
      timeout: Duration(seconds: parResponse.expiresIn ?? 300),
    );

    if (!result.isSuccess) {
      throw KrdpassAuth.instance.authResultToException(result);
    }

    final tokens = await AuthBackendService.exchangeToken(
      code: result.code!,
      state: parResponse.state ?? '',
      codeVerifier: pkce.codeVerifier,
      environment: KrdpassAuth.instance.config.environment.name,
      redirectUri: Config.redirectUri,
    );

    return _AuthResult(tokens.accessToken, tokens.idToken, tokens.refreshToken);
  }

  Future<_AuthResult> _loginClientMode() async {
    final scopes = [KrdpassScopes.openid, KrdpassScopes.profile];
    if (_includeCitizenScope) scopes.add(KrdpassScopes.citizenIdentity);
    if (_includeOfflineScope) scopes.add(KrdpassScopes.offlineAccess);

    final tokens = await KrdpassAuth.instance.signIn(
      scopes: scopes,
      timeout: const Duration(minutes: 5),
    );
    return _AuthResult(tokens.accessToken, tokens.idToken, tokens.refreshToken);
  }
}
