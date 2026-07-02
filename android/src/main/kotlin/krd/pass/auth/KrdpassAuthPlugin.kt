package krd.pass.auth

import androidx.activity.ComponentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class KrdpassAuthPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "krd.pass.krdpass_auth"
    }

    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val clientId = call.argument<String>("clientId")
                val redirectUri = call.argument<String>("redirectUri")
                val environmentName = call.argument<String>("environment")
                if (clientId != null && redirectUri != null) {
                    val environment = when (environmentName?.lowercase()) {
                        "development" -> KrdpassEnvironment.Development
                        else -> KrdpassEnvironment.Production
                    }
                    KrdpassAuth.initialize(KrdpassConfig(clientId, redirectUri, environment))
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "clientId and redirectUri are required", null)
                }
            }

            "launchKRDPassForResult" -> {
                val requestUri = call.argument<String>("requestUri")
                if (requestUri == null) {
                    result.error("INVALID_ARGS", "requestUri is required", null)
                    return
                }
                val state = call.argument<String>("state")
                if (!requireConfigured(result)) return

                // Start the flow and return immediately. The final result is delivered via
                // the "onAuthResult" callback on this channel.
                KrdpassAuth.authenticate(requestUri, state) { authResult ->
                    // Do NOT log authResult: AuthResult.Success contains the authorization code.
                    when (authResult) {
                        is AuthResult.Success -> {
                            val resultData = mutableMapOf<String, Any>(
                                "code" to authResult.code
                            )
                            authResult.state?.let { resultData["state"] = it }
                            channel?.invokeMethod("onAuthResult", resultData)
                        }
                        is AuthResult.Cancelled -> {
                            channel?.invokeMethod("onAuthResult", mapOf(
                                "error" to "cancelled",
                                "error_description" to authResult.message
                            ))
                        }
                        is AuthResult.Timeout -> {
                            channel?.invokeMethod("onAuthResult", mapOf(
                                "error" to "timeout",
                                "error_description" to authResult.message
                            ))
                        }
                        is AuthResult.Error -> {
                            channel?.invokeMethod("onAuthResult", mapOf(
                                "error" to authResult.error,
                                "error_description" to authResult.errorDescription,
                            ))
                        }
                        is AuthResult.Busy -> {
                            channel?.invokeMethod("onAuthResult", mapOf(
                                "error" to "busy",
                                "error_description" to authResult.message
                            ))
                        }
                    }
                }
                result.success(true)
            }

            "cancelAuthentication" -> {
                val timeout = (call.arguments as? Map<*, *>)?.get("timeout") as? Boolean ?: false
                KrdpassAuth.cancelPendingAuthentication(timeout)
                result.success(true)
            }

            "signIn" -> {
                val scopes = call.argument<List<String>>("scopes") ?: listOf("openid", "profile")
                if (!requireConfigured(result)) return

                KrdpassAuth.signIn(scopes) { tokenResult ->
                    tokenResult.fold(
                        onSuccess = { tokens ->
                            channel?.invokeMethod("onSignInResult", tokenMap(tokens))
                        },
                        onFailure = { exception ->
                            // Preserve the native error category so the Dart layer can surface a
                            // typed exception (cancelled/timeout/busy/...) instead of a generic failure.
                            val code = when (exception) {
                                is KrdpassError.UserCancelled -> "cancelled"
                                is KrdpassError.Timeout -> "timeout"
                                is KrdpassError.Busy -> "busy"
                                is KrdpassError.ConfigurationError -> "invalid_request"
                                is KrdpassError.NetworkError -> "network_error"
                                else -> "authentication_failed"
                            }
                            channel?.invokeMethod("onSignInResult", mapOf(
                                "error" to code,
                                "error_description" to exception.message.orEmpty()
                            ))
                        }
                    )
                }
                // Ack the invoke immediately; the real outcome arrives via onSignInResult, so a
                // never-firing SDK callback can't hang the Dart `await invokeMethod`.
                result.success(true)
            }

            "verifyToken" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("INVALID_ARGS", "token is required", null)
                    return
                }
                val clockSkewSeconds = call.argument<Number>("clockSkew")?.toLong() ?: 60L
                if (!requireConfigured(result)) return

                runAsync(result, "VERIFICATION_FAILED") {
                    sanitizeClaims(KrdpassAuth.verifyToken(token, clockSkewSeconds))
                }
            }

            "refreshTokens" -> {
                val refreshToken = call.argument<String>("refreshToken")
                if (refreshToken == null) {
                    result.error("INVALID_ARGS", "refreshToken is required", null)
                    return
                }
                val scope = call.argument<String>("scope")
                if (!requireConfigured(result)) return

                runAsync(result, "REFRESH_FAILED") {
                    tokenMap(KrdpassAuth.refreshTokens(refreshToken, scope))
                }
            }

            "revokeToken" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("INVALID_ARGS", "token is required", null)
                    return
                }
                val tokenTypeHint = call.argument<String>("tokenTypeHint")
                if (!requireConfigured(result)) return

                runAsync(result, "REVOKE_FAILED") {
                    KrdpassAuth.revokeToken(token, tokenTypeHint)
                    true
                }
            }

            "getUserInfo" -> {
                val accessToken = call.argument<String>("accessToken")
                if (accessToken == null) {
                    result.error("INVALID_ARGS", "accessToken is required", null)
                    return
                }
                if (!requireConfigured(result)) return

                runAsync(result, "USER_INFO_FAILED") {
                    val userInfo = KrdpassAuth.getUserInfo(accessToken)
                    val resultData = mutableMapOf<String, Any>("sub" to userInfo.sub)
                    userInfo.name?.let { resultData["name"] = it }
                    userInfo.givenName?.let { resultData["givenName"] = it }
                    userInfo.familyName?.let { resultData["familyName"] = it }
                    userInfo.picture?.let { resultData["picture"] = it }
                    userInfo.email?.let { resultData["email"] = it }
                    userInfo.citizenFirst?.let { resultData["citizenFirst"] = it }
                    userInfo.citizenSecond?.let { resultData["citizenSecond"] = it }
                    userInfo.citizenThird?.let { resultData["citizenThird"] = it }
                    userInfo.citizenSurname?.let { resultData["citizenSurname"] = it }
                    userInfo.citizenProfilePicture?.let { resultData["citizenProfilePicture"] = it }
                    userInfo.birthdate?.let { resultData["birthdate"] = it }
                    userInfo.sexAtBirth?.let { resultData["sexAtBirth"] = it }
                    userInfo.upn?.let { resultData["upn"] = it }
                    userInfo.did?.let { resultData["did"] = it }
                    userInfo.raw?.let {
                        // raw can hold java.util.Date / org.json types the Flutter codec can't
                        // encode; sanitizeClaims normalizes them (Date -> epoch seconds, JSON ->
                        // Map/List) before crossing the method channel. (iOS raw is already
                        // codec-safe via JSONSerialization, so its bridge passes it through.)
                        resultData["raw"] = sanitizeClaims(it)
                    }
                    resultData
                }
            }

            else -> result.notImplemented()
        }
    }

    /// Replies with NOT_CONFIGURED and returns false when [configure] hasn't run yet.
    private fun requireConfigured(result: Result): Boolean {
        if (KrdpassAuth.config == null) {
            result.error("NOT_CONFIGURED", "SDK not configured. Call configure first.", null)
            return false
        }
        return true
    }

    /// Runs [body] off the main thread, then replies on the platform thread: success with its
    /// return value, or [errorCode] + the exception message on throw. The Dispatchers.IO hop is
    /// load-bearing, not just hygiene: verifyToken is a *synchronous, blocking* JWKS call (not a
    /// suspend fun), so this is the only thing keeping it off the UI thread. Keep it for all callers.
    private fun runAsync(result: Result, errorCode: String, body: suspend () -> Any?) {
        MainScope().launch {
            try {
                result.success(withContext(Dispatchers.IO) { body() })
            } catch (e: Exception) {
                result.error(errorCode, e.message, null)
            }
        }
    }

    /// The wire shape of a token result, shared by signIn and refreshTokens.
    private fun tokenMap(tokens: KrdpassTokenResult): Map<String, Any> {
        val data = mutableMapOf<String, Any>(
            "accessToken" to tokens.accessToken,
            "tokenType" to tokens.tokenType,
            "expiresIn" to tokens.expiresIn
        )
        tokens.idToken?.let { data["idToken"] = it }
        tokens.refreshToken?.let { data["refreshToken"] = it }
        tokens.scope?.let { data["scope"] = it }
        return data
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val activity = binding.activity
        if (activity is ComponentActivity) {
            KrdpassAuth.register(activity)
        } else {
            // The stock FlutterActivity extends android.app.Activity, not ComponentActivity,
            // without registration every flow fails. Make the misconfiguration diagnosable.
            android.util.Log.w(
                "KrdpassAuthPlugin",
                "Host activity ${activity.javaClass.name} is not a ComponentActivity; " +
                    "KRDPASS auth cannot launch. Make MainActivity extend FlutterFragmentActivity.",
            )
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Keep the SDK registered across config changes so it still receives the
        // activity result when the user returns from KRDPASS.
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        val activity = binding.activity
        if (activity is ComponentActivity) {
            KrdpassAuth.register(activity)
        }
    }

    override fun onDetachedFromActivity() {}

    private fun sanitizeClaims(claims: Map<String, Any?>): Map<String, Any?> {
        return claims.mapValues { (_, value) -> sanitizeValue(value) }
    }

    private fun sanitizeValue(value: Any?): Any? {
        return when (value) {
            is java.util.Date -> value.time / 1000 // Convert Date to Seconds (JWT standard)
            is Map<*, *> -> value.entries.associate { (k, v) -> k.toString() to sanitizeValue(v) }
            is List<*> -> value.map { sanitizeValue(it) }
            is org.json.JSONArray -> {
                val list = mutableListOf<Any?>()
                for (i in 0 until value.length()) {
                    list.add(sanitizeValue(value.opt(i)))
                }
                list
            }
            is org.json.JSONObject -> {
                val map = mutableMapOf<String, Any?>()
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = sanitizeValue(value.opt(key))
                }
                map
            }
            else -> value
        }
    }
}
