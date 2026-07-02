@preconcurrency import Flutter
import UIKit
import KrdpassAuth

@MainActor
public class KrdpassAuthPlugin: NSObject, @preconcurrency FlutterPlugin, @preconcurrency FlutterSceneLifeCycleDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "krd.pass.krdpass_auth", binaryMessenger: registrar.messenger())
    let instance = KrdpassAuthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Register for both delegate styles: app-delegate for legacy hosts, scene-delegate for
    // scene-based hosts (the default since Flutter 3.35), where iOS routes the Universal Link
    // redirect to the UIScene instead of the UIApplication.
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
    instance.channel = channel
  }

  private var channel: FlutterMethodChannel?
  private var krdpassAuth: KrdpassAuth?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let args = call.arguments as? [String: Any],
            let clientId = args["clientId"] as? String,
            let redirectUri = args["redirectUri"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "clientId and redirectUri are required", details: nil))
        return
      }

      let environmentName = args["environment"] as? String
      let environment: KrdpassEnvironment
      switch environmentName?.lowercased() {
      case "development":
          environment = .development
      default:
          environment = .production
      }

      let config = KrdpassConfig(clientId: clientId, redirectUri: redirectUri, environment: environment)
      krdpassAuth = KrdpassAuth(config: config)
      result(true)

    case "launchKRDPassForResult":
      guard let args = call.arguments as? [String: Any],
            let requestUri = args["requestUri"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "requestUri is required", details: nil))
        return
      }
      let state = args["state"] as? String
      guard let auth = requireAuth(result) else { return }

      auth.authenticate(requestUri: requestUri, state: state) { [weak self] authResult in
          self?.handleAuthResult(authResult)
      }
      result(true)

    case "cancelAuthentication":
      // Best-effort cancellation/timeout of any in-flight native authentication.
      // Used by the Dart layer to stop native work when a Dart-side timeout fires.
      let timeout = (call.arguments as? [String: Any])?["timeout"] as? Bool ?? false
      krdpassAuth?.cancelPendingAuthentication(timeout: timeout)
      result(true)

    case "signIn":
      let scopes = (call.arguments as? [String: Any])?["scopes"] as? [String] ?? ["openid", "profile"]
      guard let auth = requireAuth(result) else { return }

      auth.signIn(scopes: scopes) { [weak self] tokenResult in
        switch tokenResult {
        case .success(let tokens):
          self?.channel?.invokeMethod("onSignInResult", arguments: krdpassTokenMap(tokens))
        case .failure(let error):
          // Surface the native structured code (cancelled/timeout/busy/state_mismatch/
          // invalid_id_token/nonce_mismatch/...) so the Dart layer can branch on it, with the
          // BARE message: errorDescription prefixes "Authentication failed: ..." / "Network
          // error: ...", which would diverge from the Android plugin's bare exception.message
          // for the same failure (the Dart layer displays this text verbatim).
          let description: String
          switch error {
          case .authenticationFailed(let message, _):
            description = message
          case .configurationError(let message):
            description = message
          case .networkError(let underlying):
            description = underlying.localizedDescription
          default:
            description = error.errorDescription ?? "Authentication failed"
          }
          let resultData: [String: Any] = [
            "error": error.code ?? "authentication_failed",
            "error_description": description
          ]
          self?.channel?.invokeMethod("onSignInResult", arguments: resultData)
        }
      }
      // Ack the invoke immediately; the real outcome arrives via onSignInResult, so a
      // never-firing SDK callback can't hang the Dart `await invokeMethod`.
      result(true)

    case "verifyToken":
      guard let args = call.arguments as? [String: Any],
            let token = args["token"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "token is required", details: nil))
        return
      }
      let clockSkew = args["clockSkew"] as? TimeInterval ?? 60
      guard let auth = requireAuth(result) else { return }

      runAsync(result, errorCode: "VERIFICATION_FAILED") {
        // verifyToken derives the audience from the configured clientId.
        try await auth.verifyToken(idToken: token, clockSkew: clockSkew)
      }

    case "refreshTokens":
      guard let args = call.arguments as? [String: Any],
            let refreshToken = args["refreshToken"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "refreshToken is required", details: nil))
        return
      }
      let scope = args["scope"] as? String
      guard let auth = requireAuth(result) else { return }

      runAsync(result, errorCode: "REFRESH_FAILED") {
        krdpassTokenMap(try await auth.refreshTokens(refreshToken: refreshToken, scope: scope))
      }

    case "revokeToken":
      guard let args = call.arguments as? [String: Any],
            let token = args["token"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "token is required", details: nil))
        return
      }
      let tokenTypeHint = args["tokenTypeHint"] as? String
      guard let auth = requireAuth(result) else { return }

      runAsync(result, errorCode: "REVOKE_FAILED") {
        try await auth.revokeToken(token: token, tokenTypeHint: tokenTypeHint)
        return true
      }

    case "getUserInfo":
      guard let args = call.arguments as? [String: Any],
            let accessToken = args["accessToken"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "accessToken is required", details: nil))
        return
      }
      guard let auth = requireAuth(result) else { return }

      runAsync(result, errorCode: "USER_INFO_FAILED") {
        let userInfo = try await auth.getUserInfo(accessToken: accessToken)
        var resultData: [String: Any] = [
            "sub": userInfo.sub
        ]
        if let name = userInfo.name { resultData["name"] = name }
        if let givenName = userInfo.givenName { resultData["givenName"] = givenName }
        if let familyName = userInfo.familyName { resultData["familyName"] = familyName }
        if let picture = userInfo.picture { resultData["picture"] = picture }
        if let email = userInfo.email { resultData["email"] = email }
        if let citizenFirst = userInfo.citizenFirst { resultData["citizenFirst"] = citizenFirst }
        if let citizenSecond = userInfo.citizenSecond { resultData["citizenSecond"] = citizenSecond }
        if let citizenThird = userInfo.citizenThird { resultData["citizenThird"] = citizenThird }
        if let citizenSurname = userInfo.citizenSurname { resultData["citizenSurname"] = citizenSurname }
        if let citizenProfilePicture = userInfo.citizenProfilePicture { resultData["citizenProfilePicture"] = citizenProfilePicture }
        if let birthdate = userInfo.birthdate { resultData["birthdate"] = birthdate }
        if let sexAtBirth = userInfo.sexAtBirth { resultData["sexAtBirth"] = sexAtBirth }
        if let upn = userInfo.upn { resultData["upn"] = upn }
        if let did = userInfo.did { resultData["did"] = did }
        // raw is codec-safe here (JSONSerialization types); Android sanitizes Date/JSON, see the Kt bridge.
        resultData["raw"] = userInfo.raw
        return resultData
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Replies with NOT_CONFIGURED and returns nil when `configure` hasn't run yet.
  private func requireAuth(_ result: FlutterResult) -> KrdpassAuth? {
    guard let auth = krdpassAuth else {
      result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
      return nil
    }
    return auth
  }

  /// Runs `body`, then replies: its return value on success, or `errorCode` + the error
  /// description on throw. Centralizes the do/catch -> FlutterError contract for the async methods.
  private func runAsync(_ result: @escaping FlutterResult, errorCode: String, _ body: @escaping () async throws -> Any?) {
    Task {
      do {
        result(try await body())
      } catch {
        result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
      }
    }
  }

  private func handleAuthResult(_ authResult: AuthResult) {
    var resultData: [String: Any] = [:]

    switch authResult {
    case .success(let response):
      resultData["code"] = response.code
      if let state = response.state { resultData["state"] = state }
    case .cancelled:
      resultData["error"] = AuthError.cancelled.error
      resultData["error_description"] = AuthError.cancelled.message
    case .timeout:
      resultData["error"] = AuthError.timeout.error
      resultData["error_description"] = AuthError.timeout.message
    case .error(let error):
      resultData["error"] = error.error
      resultData["error_description"] = error.message
    case .busy:
      resultData["error"] = AuthError.busy.error
      resultData["error_description"] = AuthError.busy.message
    }

    channel?.invokeMethod("onAuthResult", arguments: resultData)
  }

  // MARK: - Universal Link / deep-link handling
  //
  // The redirect back from KRDPASS arrives as a Universal Link. We funnel every delegate
  // style through these two helpers so app-delegate hosts and scene-delegate hosts behave
  // identically.

  private func handleAuthURL(_ url: URL) -> Bool {
    guard let auth = krdpassAuth, auth.canHandle(url) else { return false }
    return auth.handle(url)
  }

  private func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return false }
    return handleAuthURL(url)
  }

  // App-delegate callbacks (legacy, non-scene hosts).
  public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
    return handleUserActivity(userActivity)
  }

  public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return handleAuthURL(url)
  }

  // Scene-delegate callbacks (scene-based hosts, Flutter 3.35+).
  // `continueUserActivity` was renamed to `continue` in this SDK's UIWindowSceneDelegate.
  public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    return handleUserActivity(userActivity)
  }

  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    for context in URLContexts where handleAuthURL(context.url) {
      return true
    }
    return false
  }
}

/// The wire shape of a token result, shared by signIn and refreshTokens.
private func krdpassTokenMap(_ tokens: KrdpassTokenResult) -> [String: Any] {
  var data: [String: Any] = [
    "accessToken": tokens.accessToken,
    "tokenType": tokens.tokenType,
    "expiresIn": tokens.expiresIn
  ]
  if let idToken = tokens.idToken { data["idToken"] = idToken }
  if let refreshToken = tokens.refreshToken { data["refreshToken"] = refreshToken }
  if let scope = tokens.scope { data["scope"] = scope }
  return data
}
