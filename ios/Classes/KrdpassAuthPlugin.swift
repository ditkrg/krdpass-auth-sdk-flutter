import Flutter
import UIKit
import KrdpassAuth

@MainActor
public class KrdpassAuthPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "krd.pass.krdpass_auth", binaryMessenger: registrar.messenger())
    let instance = KrdpassAuthPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
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

      // Check URL handling capabilities just in case, but usually we just launch
      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }
      
      auth.authenticate(requestUri: requestUri, state: state) { [weak self] authResult in
          self?.handleAuthResult(authResult)
      }
      result(true)

    case "cancelAuthentication":
      // Best-effort cancellation/timeout of any in-flight native authentication.
      // Used by the Dart layer to stop native work when a Dart-side timeout fires.
      let timeout = (call.arguments as? [String: Any])?["timeout"] as? Bool ?? false
      if let auth = krdpassAuth {
        if timeout {
          auth.timeout()
        } else {
          auth.cancel()
        }
      }
      result(true)

    case "signIn":
      let scopes = (call.arguments as? [String: Any])?["scopes"] as? [String] ?? ["openid", "profile"]
      
      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }

      auth.signIn(scopes: scopes) { [weak self] tokenResult in
        switch tokenResult {
        case .success(let tokens):
          var resultData: [String: Any] = [
            "accessToken": tokens.accessToken,
            "tokenType": tokens.tokenType,
            "expiresIn": tokens.expiresIn
          ]
          if let idToken = tokens.idToken {
            resultData["idToken"] = idToken
          }
          if let refreshToken = tokens.refreshToken {
            resultData["refreshToken"] = refreshToken
          }
          if let scope = tokens.scope {
            resultData["scope"] = scope
          }

          self?.channel?.invokeMethod("onSignInResult", arguments: resultData)
          result(true)

        case .failure(let error):
          // Preserve the native error category so the Dart layer can surface a typed
          // exception (cancelled/timeout/busy/...) instead of a generic failure.
          let code: String
          switch error {
          case .userCancelled: code = "cancelled"
          case .timeout: code = "timeout"
          case .busy: code = "busy"
          case .configurationError: code = "invalid_request"
          case .networkError: code = "network_error"
          default: code = "authentication_failed"
          }
          let resultData: [String: Any] = [
            "error": code,
            "error_description": error.errorDescription ?? "Authentication failed"
          ]
          self?.channel?.invokeMethod("onSignInResult", arguments: resultData)
          result(true)
        }
      }

    case "verifyToken":
      guard let args = call.arguments as? [String: Any],
            let token = args["token"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "token is required", details: nil))
        return
      }

      let issuer = args["issuer"] as? String
      let audience = args["audience"] as? String
      let clockSkew = args["clockSkew"] as? TimeInterval ?? 60

      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }

      Task {
        do {
          let claims = try await auth.verifyToken(token, issuer: issuer, audience: audience, clockSkew: clockSkew)
          result(claims)
        } catch {
          result(FlutterError(code: "VERIFICATION_FAILED", message: error.localizedDescription, details: nil))
        }
      }

    case "refreshTokens":
      guard let args = call.arguments as? [String: Any],
            let refreshToken = args["refreshToken"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "refreshToken is required", details: nil))
        return
      }
      let scope = args["scope"] as? String

      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }

      Task {
        do {
          let tokens = try await auth.refreshTokens(refreshToken: refreshToken, scope: scope)
          var resultData: [String: Any] = [
            "accessToken": tokens.accessToken,
            "tokenType": tokens.tokenType,
            "expiresIn": tokens.expiresIn
          ]
          if let idToken = tokens.idToken { resultData["idToken"] = idToken }
          if let refreshToken = tokens.refreshToken { resultData["refreshToken"] = refreshToken }
          if let scope = tokens.scope { resultData["scope"] = scope }
          
          result(resultData)
        } catch {
          result(FlutterError(code: "REFRESH_FAILED", message: error.localizedDescription, details: nil))
        }
      }

    case "revokeToken":
      guard let args = call.arguments as? [String: Any],
            let token = args["token"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "token is required", details: nil))
        return
      }
      let tokenTypeHint = args["tokenTypeHint"] as? String

      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }

      Task {
        do {
          try await auth.revokeToken(token: token, tokenTypeHint: tokenTypeHint)
          result(true)
        } catch {
          result(FlutterError(code: "REVOKE_FAILED", message: error.localizedDescription, details: nil))
        }
      }

    case "getUserInfo":
      guard let args = call.arguments as? [String: Any],
            let accessToken = args["accessToken"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "accessToken is required", details: nil))
        return
      }

      guard let auth = krdpassAuth else {
        result(FlutterError(code: "NOT_CONFIGURED", message: "SDK not configured. Call configure first.", details: nil))
        return
      }

      Task {
        do {
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
          
          resultData["raw"] = userInfo.raw
          
          result(resultData)
        } catch {
          result(FlutterError(code: "USER_INFO_FAILED", message: error.localizedDescription, details: nil))
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleAuthResult(_ authResult: AuthResult) {
    var resultData: [String: Any] = [:]
    
    switch authResult {
    case .success(let response):
      resultData["code"] = response.code
      if let state = response.state {
        resultData["state"] = state
      }
    case .cancelled:
      resultData["error"] = "cancelled"
      resultData["error_description"] = "User cancelled authorization"
    case .timeout:
      resultData["error"] = "timeout"
      resultData["error_description"] = "Authentication timed out"
    case .error(let error):
      resultData["error"] = error.error ?? "authorization_error"
      resultData["error_description"] = error.message
    case .busy:
      resultData["error"] = "busy"
      resultData["error_description"] = "Authentication already in progress"
    }
    
    channel?.invokeMethod("onAuthResult", arguments: resultData)
  }
  
  // MARK: - App Delegate Methods
  
  public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      if let auth = krdpassAuth, auth.canHandle(url) {
        return auth.handle(url)
      }
    }
    return false
  }
  
  public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if let auth = krdpassAuth, auth.canHandle(url) {
      return auth.handle(url)
    }
    return false
  }
}
