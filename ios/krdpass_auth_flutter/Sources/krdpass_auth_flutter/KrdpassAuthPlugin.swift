@preconcurrency import Flutter
import UIKit
import KrdpassAuth

@MainActor
public class KrdpassAuthPlugin: NSObject, @preconcurrency FlutterPlugin, @preconcurrency FlutterSceneLifeCycleDelegate {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "krd.pass.krdpass_auth", binaryMessenger: registrar.messenger())
    let instance = KrdpassAuthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Both delegate styles: scene-based hosts (default since Flutter 3.35) route the
    // Universal Link redirect to the UIScene, legacy hosts to the UIApplication.
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
    instance.channel = channel
  }

  private var channel: FlutterMethodChannel?
  private var krdpassAuth: KrdpassAuth?
  // In-flight runAsync work, so detachFromEngine can cancel it instead of letting each
  // task reply into a dead channel. Mirrors the Kotlin bridge's scopeJob.cancel().
  private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    // Without this the plugin, its channel and the core outlive the engine, leaking one
    // of each per engine in an add-to-app host.
    for task in inFlightTasks.values { task.cancel() }
    inFlightTasks.removeAll()
    channel?.setMethodCallHandler(nil)
    channel = nil
    krdpassAuth = nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure": configure(call, result)
    case "launchKRDPassForResult": launchKRDPassForResult(call, result)
    case "cancelAuthentication": cancelAuthentication(call, result)
    case "signIn": signIn(call, result)
    case "verifyToken": verifyToken(call, result)
    case "refreshTokens": refreshTokens(call, result)
    case "revokeToken": revokeToken(call, result)
    case "getUserInfo": getUserInfo(call, result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func configure(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let clientId = requireArg(call, result, "clientId"),
          let redirectUri = requireArg(call, result, "redirectUri") else { return }

    let environmentName = (call.arguments as? [String: Any])?["environment"] as? String
    guard let environment = krdpassEnvironment(environmentName) else {
      result(FlutterError(
        code: "invalid_request",
        message: "unknown environment '\(environmentName ?? "")'; expected 'production' or 'development'",
        details: nil))
      return
    }

    let config = KrdpassConfig(clientId: clientId, redirectUri: redirectUri, environment: environment)
    krdpassAuth = KrdpassAuth(config: config)
    result(true)
  }

  private func launchKRDPassForResult(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let requestUri = requireArg(call, result, "requestUri") else { return }
    guard let state = (call.arguments as? [String: Any])?["state"] as? String,
      !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(FlutterError(
        code: "invalid_request",
        message: "state is required and cannot be blank. Pass the state returned by your backend's PAR call, or use signIn().",
        details: nil))
      return
    }
    // Dart sends whole milliseconds; the core's `timeout` is seconds. Absent falls
    // through to the core's own default rather than hardcoding it here.
    let timeoutMillis = (call.arguments as? [String: Any])?["timeoutMillis"] as? TimeInterval
    guard let auth = requireAuth(result) else { return }

    let authCompletion: (AuthResult) -> Void = { [weak self] authResult in
        self?.handleAuthResult(authResult)
    }
    if let timeoutMillis {
      auth.authenticate(requestUri: requestUri, state: state, timeout: timeoutMillis / 1000, completion: authCompletion)
    } else {
      auth.authenticate(requestUri: requestUri, state: state, completion: authCompletion)
    }
    result(true)
  }

  private func cancelAuthentication(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    // Best-effort: stops native work when a Dart-side timeout or cancel fires.
    let timeout = (call.arguments as? [String: Any])?["timeout"] as? Bool ?? false
    krdpassAuth?.cancelPendingAuthentication(timeout: timeout)
    result(true)
  }

  private func signIn(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let scopes = args?["scopes"] as? [String] ?? ["openid", "profile"]
    let timeoutMillis = args?["timeoutMillis"] as? TimeInterval
    guard let auth = requireAuth(result) else { return }

    let signInCompletion: (Result<KrdpassTokenResult, KrdpassError>) -> Void = { [weak self] tokenResult in
      switch tokenResult {
      case .success(let tokens):
        self?.channel?.invokeMethod("onSignInResult", arguments: krdpassTokenMap(tokens))
      case .failure(let error):
        self?.channel?.invokeMethod("onSignInResult", arguments: krdpassSignInErrorMap(error))
      }
    }
    if let timeoutMillis {
      auth.signIn(scopes: scopes, timeout: timeoutMillis / 1000, completion: signInCompletion)
    } else {
      auth.signIn(scopes: scopes, completion: signInCompletion)
    }
    // Ack now so a never-firing SDK callback can't hang the Dart `await invokeMethod`;
    // the outcome arrives via onSignInResult.
    result(true)
  }

  private func verifyToken(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let token = requireArg(call, result, "token") else { return }
    let clockSkew = (call.arguments as? [String: Any])?["clockSkew"] as? TimeInterval ?? 60
    guard let auth = requireAuth(result) else { return }

    runAsync(result, errorCode: "verification_failed") {
      // jsonObject per claim, same reason krdpassUserInfoMap sends rawJsonObject: the
      // claims are [String: JSONValue], a Swift enum the Flutter codec cannot encode.
      // Sending them raw compiles and then silently fails to serialize.
      try await auth.verifyToken(idToken: token, clockSkew: clockSkew).mapValues(\.jsonObject)
    }
  }

  private func refreshTokens(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let refreshToken = requireArg(call, result, "refreshToken") else { return }
    let scope = (call.arguments as? [String: Any])?["scope"] as? String
    guard let auth = requireAuth(result) else { return }

    runAsync(result, errorCode: "refresh_failed") {
      krdpassTokenMap(try await auth.refreshTokens(refreshToken: refreshToken, scope: scope))
    }
  }

  private func revokeToken(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let token = requireArg(call, result, "token") else { return }
    let tokenTypeHint = (call.arguments as? [String: Any])?["tokenTypeHint"] as? String
    guard let auth = requireAuth(result) else { return }

    runAsync(result, errorCode: "revoke_failed") {
      try await auth.revokeToken(token: token, tokenTypeHint: tokenTypeHint)
      return true
    }
  }

  private func getUserInfo(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let accessToken = requireArg(call, result, "accessToken") else { return }
    guard let auth = requireAuth(result) else { return }

    runAsync(result, errorCode: "user_info_failed") {
      krdpassUserInfoMap(try await auth.getUserInfo(accessToken: accessToken))
    }
  }

  private func requireAuth(_ result: FlutterResult) -> KrdpassAuth? {
    guard let auth = krdpassAuth else {
      result(FlutterError(code: "invalid_request", message: "SDK not configured. Call configure first.", details: nil))
      return nil
    }
    return auth
  }

  private func requireArg(_ call: FlutterMethodCall, _ result: FlutterResult, _ key: String) -> String? {
    guard let value = (call.arguments as? [String: Any])?[key] as? String else {
      result(FlutterError(code: "invalid_request", message: "\(key) is required", details: nil))
      return nil
    }
    return value
  }

  /// Runs `body`, then replies: its return value on success, or a wire error on throw.
  /// Replies carry no `message`, only `details`: these failures hold raw CAS bodies,
  /// and the Dart layer displays `message` verbatim.
  // The class is @MainActor, so the Task below inherits that isolation while `body` runs
  // nonisolated; `sending` is what lets its result cross that boundary.
  private func runAsync(_ result: @escaping FlutterResult, errorCode fallbackCode: String, _ body: @escaping () async throws -> sending Any?) {
    let id = UUID()
    inFlightTasks[id] = Task { [weak self] in
      defer { self?.inFlightTasks[id] = nil }
      do {
        result(try await body())
      } catch {
        // The task is cancelled from detachFromEngine, so the channel is already torn down: replying would hit a dead channel.
        if error is CancellationError { return }
        result(FlutterError(
          code: Self.wireCode(error) ?? fallbackCode,
          message: nil,
          details: error.localizedDescription))
      }
    }
  }

  /// Nil is what lets a permanent CAS failure fall through to the caller's per-call fallback
  /// code; do not substitute a catch-all code for it.
  private static func wireCode(_ error: Error) -> String? {
    if let krdpassError = error as? KrdpassError { return krdpassError.code }
    if error is URLError { return "network_error" }
    return nil
  }

  private func handleAuthResult(_ authResult: AuthResult) {
    channel?.invokeMethod("onAuthResult", arguments: krdpassAuthResultMap(authResult))
  }

  // MARK: - Universal Link / deep-link handling
  //
  // Every delegate style funnels through these two helpers so app-delegate and
  // scene-delegate hosts behave identically.
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

// The wire mapping below is free of plugin state, matching the Kotlin bridge's layout.

private func krdpassAuthResultMap(_ authResult: AuthResult) -> [String: Any] {
  let code: String
  switch authResult {
  case .success(let response):
    var data: [String: Any] = ["code": response.code]
    if let state = response.state { data["state"] = state }
    return data
  case .cancelled: code = "cancelled"
  case .timeout: code = "timeout"
  case .busy: code = "busy"
  case .error(let error):
    return ["error": error.error, "error_description": error.message]
  }
  // The bare cases carry no payload; `message` surfaces the core's canonical text for them.
  return ["error": code, "error_description": authResult.message ?? code]
}

/// Rejected rather than defaulted: a typo like "developement" must not silently point a test build at live
/// citizen endpoints.
private func krdpassEnvironment(_ name: String?) -> KrdpassEnvironment? {
  switch name?.lowercased() {
  case "development": return .development
  case "production", nil: return .production
  default: return nil
  }
}

/// Forwards the structured code with the BARE
/// message: `errorDescription` prefixes "Authentication failed: ..." and would diverge
/// from Android's bare exception.message, which Dart displays verbatim.
private func krdpassSignInErrorMap(_ error: KrdpassError) -> [String: Any] {
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
  return [
    "error": error.code ?? "authentication_failed",
    "error_description": description
  ]
}

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

/// citizenFullName is deliberately absent: the
/// Dart model derives it from the four name parts, and sending it would add a second
/// source.
private func krdpassUserInfoMap(_ userInfo: KrdpassUserInfo) -> [String: Any] {
  var data: [String: Any] = [
    "sub": userInfo.sub
  ]
  if let name = userInfo.name { data["name"] = name }
  if let givenName = userInfo.givenName { data["givenName"] = givenName }
  if let familyName = userInfo.familyName { data["familyName"] = familyName }
  if let picture = userInfo.picture { data["picture"] = picture }
  if let email = userInfo.email { data["email"] = email }
  if let citizenFirst = userInfo.citizenFirst { data["citizenFirst"] = citizenFirst }
  if let citizenSecond = userInfo.citizenSecond { data["citizenSecond"] = citizenSecond }
  if let citizenThird = userInfo.citizenThird { data["citizenThird"] = citizenThird }
  if let citizenSurname = userInfo.citizenSurname { data["citizenSurname"] = citizenSurname }
  if let citizenProfilePicture = userInfo.citizenProfilePicture { data["citizenProfilePicture"] = citizenProfilePicture }
  if let birthdate = userInfo.birthdate { data["birthdate"] = birthdate }
  if let sexAtBirth = userInfo.sexAtBirth { data["sexAtBirth"] = sexAtBirth }
  if let upn = userInfo.upn { data["upn"] = upn }
  data["upns"] = userInfo.upns
  if let did = userInfo.did { data["did"] = did }
  // rawJsonObject, not raw: raw is [String: JSONValue], a Swift enum the Flutter codec
  // cannot encode. Assigning it compiles (data is [String: Any]) and then silently fails
  // to serialize.
  data["raw"] = userInfo.rawJsonObject
  return data
}
