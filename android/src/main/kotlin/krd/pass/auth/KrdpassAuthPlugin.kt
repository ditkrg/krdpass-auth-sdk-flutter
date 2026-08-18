package krd.pass.auth

import androidx.activity.ComponentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class KrdpassAuthPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "krd.pass.krdpass_auth"
        private const val TAG = "KrdpassAuthPlugin"

        // Spelled out rather than read from the core's KrdpassMessages, which is internal to it.
        private const val STATE_REQUIRED =
            "state is required and cannot be blank. Pass the state returned by your backend's " +
                "PAR call, or use signIn()."
    }

    private var channel: MethodChannel? = null

    // One scope for the plugin's lifetime, cancelled in onDetachedFromEngine;
    // SupervisorJob so one failed call cannot cancel the others.
    private val scopeJob = SupervisorJob()
    private val scope = CoroutineScope(scopeJob + Dispatchers.Main)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "launchKRDPassForResult" -> launchKrdpassForResult(call, result)
            "cancelAuthentication" -> cancelAuthentication(call, result)
            "signIn" -> signIn(call, result)
            "verifyToken" -> verifyToken(call, result)
            "refreshTokens" -> refreshTokens(call, result)
            "revokeToken" -> revokeToken(call, result)
            "getUserInfo" -> getUserInfo(call, result)
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: Result) {
        val clientId = requireArg(call, result, "clientId") ?: return
        val redirectUri = requireArg(call, result, "redirectUri") ?: return
        val environmentName = call.argument<String>("environment")
        val environment = parseEnvironment(environmentName)
        if (environment == null) {
            result.error(
                "invalid_request",
                "unknown environment '$environmentName'; expected 'production' or 'development'",
                null,
            )
            return
        }
        KrdpassAuth.initialize(KrdpassConfig(clientId, redirectUri, environment))
        result.success(true)
    }

    private fun launchKrdpassForResult(call: MethodCall, result: Result) {
        val requestUri = requireArg(call, result, "requestUri") ?: return
        val state = call.argument<String>("state")
        if (state.isNullOrBlank()) {
            result.error("invalid_request", STATE_REQUIRED, null)
            return
        }
        val timeoutMillis = call.argument<Number>("timeoutMillis")?.toLong()
            ?: KrdpassAuth.DEFAULT_TIMEOUT_MILLIS
        if (!requireConfigured(result)) return

        KrdpassAuth.authenticate(requestUri, state, timeoutMillis) { authResult ->
            // Do NOT log authResult: AuthResult.Success contains the authorization code.
            channel?.invokeMethod("onAuthResult", authResultMap(authResult))
        }
        result.success(true)
    }

    private fun cancelAuthentication(call: MethodCall, result: Result) {
        val timeout = call.argument<Boolean>("timeout") ?: false
        KrdpassAuth.cancelPendingAuthentication(timeout)
        result.success(true)
    }

    private fun signIn(call: MethodCall, result: Result) {
        val scopes = call.argument<List<String>>("scopes") ?: listOf("openid", "profile")
        val timeoutMillis = call.argument<Number>("timeoutMillis")?.toLong()
            ?: KrdpassAuth.DEFAULT_TIMEOUT_MILLIS
        if (!requireConfigured(result)) return

        // Named argument required: signIn is (scopes, timeoutMillis, callback),
        // so a positional second argument resolves to the suspend overload.
        KrdpassAuth.signIn(scopes, timeoutMillis, callback = object : SignInCallback {
            override fun onSuccess(tokens: KrdpassTokenResult) {
                channel?.invokeMethod("onSignInResult", tokenMap(tokens))
            }

            override fun onFailure(error: Throwable) {
                channel?.invokeMethod("onSignInResult", signInErrorMap(error))
            }
        })
        // Ack now so a never-firing SDK callback can't hang the Dart
        // `await invokeMethod`; the outcome arrives via onSignInResult.
        result.success(true)
    }

    private fun verifyToken(call: MethodCall, result: Result) {
        val token = requireArg(call, result, "token") ?: return
        val clockSkewSeconds = call.argument<Number>("clockSkew")?.toLong() ?: 60L
        if (!requireConfigured(result)) return

        runAsync(result, "verification_failed") {
            sanitizeClaims(KrdpassAuth.verifyToken(token, clockSkewSeconds))
        }
    }

    private fun refreshTokens(call: MethodCall, result: Result) {
        val refreshToken = requireArg(call, result, "refreshToken") ?: return
        val scope = call.argument<String>("scope")
        if (!requireConfigured(result)) return

        runAsync(result, "refresh_failed") {
            tokenMap(KrdpassAuth.refreshTokens(refreshToken, scope))
        }
    }

    private fun revokeToken(call: MethodCall, result: Result) {
        val token = requireArg(call, result, "token") ?: return
        val tokenTypeHint = call.argument<String>("tokenTypeHint")
        if (!requireConfigured(result)) return

        runAsync(result, "revoke_failed") {
            KrdpassAuth.revokeToken(token, tokenTypeHint)
            true
        }
    }

    private fun getUserInfo(call: MethodCall, result: Result) {
        val accessToken = requireArg(call, result, "accessToken") ?: return
        if (!requireConfigured(result)) return

        runAsync(result, "user_info_failed") {
            userInfoMap(KrdpassAuth.getUserInfo(accessToken))
        }
    }

    private fun requireConfigured(result: Result): Boolean {
        if (KrdpassAuth.config == null) {
            result.error("invalid_request", "SDK not configured. Call configure first.", null)
            return false
        }
        return true
    }

    private fun requireArg(call: MethodCall, result: Result, key: String): String? {
        val value = call.argument<String>(key)
        if (value == null) result.error("invalid_request", "$key is required", null)
        return value
    }

    /**
     * Runs [body] off the main thread, then replies on the platform thread. The
     * Dispatchers.IO hop is the only thing keeping verifyToken's synchronous, blocking
     * JWKS call off the UI thread. Replies carry no `message`, only `details`: these
     * failures hold raw CAS bodies, and the Dart layer displays `message` verbatim.
     */
    private fun runAsync(result: Result, fallbackCode: String, body: suspend () -> Any?) {
        scope.launch {
            val value = try {
                withContext(Dispatchers.IO) { body() }
            } catch (e: CancellationException) {
                // The scope is cancelled from onDetachedFromEngine, so the channel is
                // already torn down: swallowing this replies on a dead channel.
                throw e
            } catch (e: Throwable) {
                // Throwable, not Exception: a linkage Error from a consumer's shrinker
                // config must still reply to Dart instead of crashing the host app.
                result.error(wireCode(e) ?: fallbackCode, null, e.message)
                return@launch
            }
            // The reply sits outside the try: if success() itself throws, replying error()
            // from the catch would be a second reply on the same call.
            result.success(value)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scopeJob.cancel()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        register(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // Deliberately empty: stay registered so the activity result still arrives.
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        register(binding.activity)
    }

    override fun onDetachedFromActivity() {}

    /**
     * Registers the activity-result launcher, logging instead of crashing the host when
     * it cannot be registered: both failures are host misconfiguration, and what matters
     * is that the app survives engine attach and says why sign-in will not work.
     */
    private fun register(activity: android.app.Activity) {
        if (activity !is ComponentActivity) {
            // Stock FlutterActivity is not a ComponentActivity, so every flow fails.
            android.util.Log.w(
                TAG,
                "Host activity ${activity.javaClass.name} is not a ComponentActivity; " +
                    "KRDPASS auth cannot launch. Make MainActivity extend FlutterFragmentActivity.",
            )
            return
        }
        try {
            KrdpassAuth.register(activity)
        } catch (e: IllegalStateException) {
            // registerForActivityResult refuses an already-STARTED activity, the normal
            // case for add-to-app hosts attaching a cached engine.
            android.util.Log.e(
                TAG,
                "KRDPASS auth could not register on ${activity.javaClass.name}: the activity was " +
                    "already started when the Flutter engine attached. Attach the engine before " +
                    "onStart (see the add-to-app note in the plugin README).",
                e,
            )
        }
    }
}

// The wire mapping below is free of plugin state: top-level so the unit tests can call
// it without standing up a MethodChannel or an Android main looper.

/**
 * Rejected rather than defaulted: a typo like "developement" must not silently point a test build at live
 * citizen endpoints.
 */
internal fun parseEnvironment(name: String?): KrdpassEnvironment? = when (name?.lowercase()) {
    "development" -> KrdpassEnvironment.Development
    "production", null -> KrdpassEnvironment.Production
    else -> null
}

/**
 * Null is what lets a permanent CAS failure fall through to the caller's per-call fallback code;
 * do not substitute a catch-all code for it.
 */
internal fun wireCode(error: Throwable): String? = when (error) {
    is KrdpassError -> error.code
    is java.io.IOException -> "network_error"
    else -> null
}

internal fun authResultMap(result: AuthResult): Map<String, Any?> = when (result) {
    // An absent state is omitted rather than sent as null, same as the iOS bridge.
    is AuthResult.Success -> buildMap {
        put("code", result.code)
        result.state?.let { put("state", it) }
    }
    is AuthResult.Cancelled -> mapOf("error" to "cancelled", "error_description" to result.message)
    is AuthResult.Timeout -> mapOf("error" to "timeout", "error_description" to result.message)
    is AuthResult.Busy -> mapOf("error" to "busy", "error_description" to result.message)
    // message, not errorDescription: the core falls back to the error code when CAS
    // sent no description, so the wire never carries a null one.
    is AuthResult.Error -> mapOf("error" to result.error, "error_description" to result.message)
}

internal fun signInErrorMap(error: Throwable): Map<String, Any?> = mapOf(
    "error" to (wireCode(error) ?: "authentication_failed"),
    // A raw Throwable's message can be null or blank, and a blank error_description
    // renders as "Failed: " in an app that displays it verbatim.
    "error_description" to (error.message?.takeIf { it.isNotBlank() } ?: "Authentication failed"),
)

internal fun tokenMap(tokens: KrdpassTokenResult): Map<String, Any> = buildMap {
    put("accessToken", tokens.accessToken)
    put("tokenType", tokens.tokenType)
    put("expiresIn", tokens.expiresIn)
    tokens.idToken?.let { put("idToken", it) }
    tokens.refreshToken?.let { put("refreshToken", it) }
    tokens.scope?.let { put("scope", it) }
}

/**
 * citizenFullName is deliberately absent: the Dart
 * model derives it from the four name parts, and sending it would add a second source.
 */
internal fun userInfoMap(userInfo: KrdpassUserInfo): Map<String, Any> = buildMap {
    put("sub", userInfo.sub)
    userInfo.name?.let { put("name", it) }
    userInfo.givenName?.let { put("givenName", it) }
    userInfo.familyName?.let { put("familyName", it) }
    userInfo.picture?.let { put("picture", it) }
    userInfo.email?.let { put("email", it) }
    userInfo.citizenFirst?.let { put("citizenFirst", it) }
    userInfo.citizenSecond?.let { put("citizenSecond", it) }
    userInfo.citizenThird?.let { put("citizenThird", it) }
    userInfo.citizenSurname?.let { put("citizenSurname", it) }
    userInfo.citizenProfilePicture?.let { put("citizenProfilePicture", it) }
    userInfo.birthdate?.let { put("birthdate", it) }
    userInfo.sexAtBirth?.let { put("sexAtBirth", it) }
    userInfo.upn?.let { put("upn", it) }
    put("upns", userInfo.upns)
    userInfo.did?.let { put("did", it) }
    // raw holds java.util.Date / org.json types the Flutter codec cannot encode;
    // sanitizeClaims normalizes them first.
    put("raw", sanitizeClaims(userInfo.raw))
}

internal fun sanitizeClaims(claims: Map<String, Any?>): Map<String, Any?> =
    claims.mapValues { (_, value) -> sanitizeValue(value) }

private fun sanitizeValue(value: Any?): Any? {
    return when (value) {
        is java.util.Date -> value.time / 1000 // JWT claims are epoch seconds
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
