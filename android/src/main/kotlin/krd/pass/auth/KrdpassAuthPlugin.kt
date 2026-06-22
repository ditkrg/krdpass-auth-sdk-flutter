package krd.pass.auth

import androidx.activity.ComponentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import krd.pass.auth.AuthResult
import krd.pass.auth.KrdpassAuth
import krd.pass.auth.KrdpassConfig
import krd.pass.auth.KrdpassEnvironment
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class KrdpassAuthPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "krd.pass.krdpass_auth"
    }

    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "launchKRDPassForResult") {
            val requestUri = call.argument<String>("requestUri")
            if (requestUri == null) {
                result.error("INVALID_ARGS", "requestUri is required", null)
                return
            }

            val state = call.argument<String>("state")

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured. Call configure first.", null)
                return
            }

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
                            "error_description" to "User cancelled authorization"
                        ))
                    }
                    is AuthResult.Timeout -> {
                        channel?.invokeMethod("onAuthResult", mapOf(
                            "error" to "timeout",
                            "error_description" to "Authentication timed out"
                        ))
                    }
                    is AuthResult.Error -> {
                        channel?.invokeMethod("onAuthResult", mapOf(
                            "error" to authResult.error,
                            "error_description" to authResult.description
                        ))
                    }
                    is AuthResult.Busy -> {
                        channel?.invokeMethod("onAuthResult", mapOf(
                            "error" to "busy",
                            "error_description" to "Another authentication is already in progress"
                        ))
                    }
                }
            }
            result.success(true)
        } else if (call.method == "cancelAuthentication") {
            val timeout = (call.arguments as? Map<*, *>)?.get("timeout") as? Boolean ?: false
            if (timeout) {
                KrdpassAuth.timeout()
            } else {
                KrdpassAuth.cancel()
            }
            result.success(true)
        } else if (call.method == "signIn") {
            val scopes = call.argument<List<String>>("scopes") ?: listOf("openid", "profile")

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured. Call configure first.", null)
                return
            }

            KrdpassAuth.signIn(scopes) { tokenResult ->
                tokenResult.fold(
                    onSuccess = { tokens ->
                        val resultData = mutableMapOf<String, Any>(
                            "accessToken" to tokens.accessToken,
                            "tokenType" to tokens.tokenType,
                            "expiresIn" to tokens.expiresIn
                        )
                        tokens.idToken?.let { resultData["idToken"] = it }
                        tokens.refreshToken?.let { resultData["refreshToken"] = it }
                        tokens.scope?.let { resultData["scope"] = it }

                        channel?.invokeMethod("onSignInResult", resultData)
                        result.success(true)
                    },
                    onFailure = { exception ->
                        channel?.invokeMethod("onSignInResult", mapOf(
                            "error" to "authentication_failed",
                            "error_description" to exception.message.orEmpty()
                        ))
                        result.success(true)
                    }
                )
            }
        } else if (call.method == "configure") {
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
        } else if (call.method == "verifyToken") {
            val token = call.argument<String>("token")
            if (token == null) {
                result.error("INVALID_ARGS", "token is required", null)
                return
            }

            val issuer = call.argument<String>("issuer")
            val audience = call.argument<String>("audience")
            val clockSkewSeconds = call.argument<Number>("clockSkew")?.toLong() ?: 60L

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured", null)
                return
            }

            MainScope().launch {
                try {
                    val claims = withContext(Dispatchers.IO) {
                        KrdpassAuth.verifyToken(token, issuer, audience, clockSkewSeconds)
                    }
                    result.success(sanitizeClaims(claims))
                } catch (e: Exception) {
                    result.error("VERIFICATION_FAILED", e.message, null)
                }
            }
        } else if (call.method == "refreshTokens") {
            val refreshToken = call.argument<String>("refreshToken")
            if (refreshToken == null) {
                 result.error("INVALID_ARGS", "refreshToken is required", null)
                 return
            }
            val scope = call.argument<String>("scope")

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured", null)
                return
            }

            MainScope().launch {
                try {
                    val tokenResult = withContext(Dispatchers.IO) {
                        KrdpassAuth.refreshTokens(refreshToken, scope)
                    }
                    val resultData = mutableMapOf<String, Any>(
                        "accessToken" to tokenResult.accessToken,
                        "tokenType" to tokenResult.tokenType,
                        "expiresIn" to tokenResult.expiresIn
                    )
                    tokenResult.idToken?.let { resultData["idToken"] = it }
                    tokenResult.refreshToken?.let { resultData["refreshToken"] = it }
                    tokenResult.scope?.let { resultData["scope"] = it }
                    
                    result.success(resultData)
                } catch (e: Exception) {
                    result.error("REFRESH_FAILED", e.message, null)
                }
            }
        } else if (call.method == "revokeToken") {
            val token = call.argument<String>("token")
            if (token == null) {
                 result.error("INVALID_ARGS", "token is required", null)
                 return
            }
            val tokenTypeHint = call.argument<String>("tokenTypeHint")

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured", null)
                return
            }

            MainScope().launch {
                try {
                    withContext(Dispatchers.IO) {
                        KrdpassAuth.revokeToken(token, tokenTypeHint)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("REVOKE_FAILED", e.message, null)
                }
            }
        } else if (call.method == "getUserInfo") {
            val accessToken = call.argument<String>("accessToken")
            if (accessToken == null) {
                 result.error("INVALID_ARGS", "accessToken is required", null)
                 return
            }

            if (KrdpassAuth.config == null) {
                result.error("NOT_CONFIGURED", "SDK not configured", null)
                return
            }

            MainScope().launch {
                try {
                    val userInfo = withContext(Dispatchers.IO) {
                        KrdpassAuth.getUserInfo(accessToken)
                    }
                    val resultData = mutableMapOf<String, Any>(
                        "sub" to userInfo.sub
                    )
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
                        // Sanitize raw usage of Date internally if any? 
                        // Raw is Map<String, Any?>, check if sanitizeClaims is needed
                        resultData["raw"] = sanitizeClaims(it) 
                    }
                    
                    result.success(resultData)
                } catch (e: Exception) {
                    result.error("USER_INFO_FAILED", e.message, null)
                }
            }
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        val activity = binding.activity
        if (activity is ComponentActivity) {
            KrdpassAuth.register(activity)
            android.util.Log.d("KRDPassPlugin", "KrdpassAuth registered for activity: $activity")

            // Bridge native logs to Logcat
            KrdpassAuth.logger = object : krd.pass.auth.KrdpassLogger {
                override fun log(level: String, message: String) {
                    android.util.Log.d("KRDPassSDK", "[$level] $message")
                }
            }
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Do not unregister during config changes; keep the SDK ready to receive results.
        // to receive the activity result when the user returns from KRDPass!
        android.util.Log.d("KRDPassPlugin", "Activity detached for config changes - preserving KrdpassAuth")
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        android.util.Log.d("KRDPassPlugin", "Activity reattached after config changes")
        activityBinding = binding
        val activity = binding.activity
        if (activity is ComponentActivity) {
            KrdpassAuth.register(activity)
        }
    }

    override fun onDetachedFromActivity() {
        android.util.Log.d("KRDPassPlugin", "Activity fully detached - destroying KrdpassAuth")
        activityBinding = null
    }

    private fun sanitizeClaims(claims: Map<String, Any?>): Map<String, Any?> {
        return claims.mapValues { (_, value) -> sanitizeValue(value) }
    }

    private fun sanitizeValue(value: Any?): Any? {
        return when (value) {
            is java.util.Date -> value.time / 1000 // Convert Date to Seconds (JWT standard)
            is Map<*, *> -> (value as Map<String, Any?>).mapValues { (_, v) -> sanitizeValue(v) }
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
