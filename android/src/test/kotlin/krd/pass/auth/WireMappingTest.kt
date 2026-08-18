package krd.pass.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Locks the wire shape the Android bridge pushes over the method channel. The Dart tests
 * mock the channel, so these run against the real core types, the half nothing else covers.
 */
class WireMappingTest {

    @Test
    fun `wireCode returns the canonical code for every KrdpassError`() {
        assertEquals("cancelled", wireCode(KrdpassError.UserCancelled()))
        assertEquals("timeout", wireCode(KrdpassError.Timeout()))
        assertEquals("busy", wireCode(KrdpassError.Busy()))
        assertEquals("network_error", wireCode(KrdpassError.NetworkError("no route")))
        assertEquals("invalid_request", wireCode(KrdpassError.ConfigurationError("blank state")))
    }

    @Test
    fun `wireCode passes an AuthenticationFailed code through`() {
        assertEquals(
            "state_mismatch",
            wireCode(KrdpassError.AuthenticationFailed("mismatch", "state_mismatch")),
        )
    }

    @Test
    fun `wireCode is null for a failure with no code`() {
        // Null is load-bearing: it lets the caller apply its own fallback code
        // (refresh_failed, revoke_failed, ...) instead of a catch-all.
        assertNull(wireCode(KrdpassError.AuthenticationFailed("CAS said no")))
        assertNull(wireCode(IllegalStateException("boom")))
    }

    @Test
    fun `wireCode treats a plain IO failure as retryable`() {
        assertEquals("network_error", wireCode(java.io.IOException("socket closed")))
    }

    @Test
    fun `parseEnvironment ignores case and defaults to production`() {
        assertEquals(KrdpassEnvironment.Production, parseEnvironment("production"))
        assertEquals(KrdpassEnvironment.Production, parseEnvironment("PRODUCTION"))
        assertEquals(KrdpassEnvironment.Production, parseEnvironment(null))
        assertEquals(KrdpassEnvironment.Development, parseEnvironment("development"))
        assertEquals(KrdpassEnvironment.Development, parseEnvironment("Development"))
    }

    @Test
    fun `parseEnvironment rejects anything else`() {
        // A typo must not silently point a test build at live citizen endpoints.
        assertNull(parseEnvironment("developement"))
        assertNull(parseEnvironment("dev"))
        assertNull(parseEnvironment(""))
    }

    @Test
    fun `authResultMap sends the code and omits an absent state`() {
        assertEquals(
            mapOf("code" to "abc", "state" to "xyz"),
            authResultMap(AuthResult.Success("abc", "xyz")),
        )
        assertEquals(mapOf("code" to "abc"), authResultMap(AuthResult.Success("abc")))
    }

    @Test
    fun `authResultMap sends the canonical message for the payload-free results`() {
        assertEquals(
            mapOf("error" to "cancelled", "error_description" to "Authentication was cancelled"),
            authResultMap(AuthResult.Cancelled),
        )
        assertEquals(
            mapOf("error" to "timeout", "error_description" to "Authentication timed out"),
            authResultMap(AuthResult.Timeout),
        )
        assertEquals(
            mapOf(
                "error" to "busy",
                "error_description" to "Another authentication is already in progress",
            ),
            authResultMap(AuthResult.Busy),
        )
    }

    @Test
    fun `authResultMap never sends a null error_description`() {
        assertEquals(
            mapOf("error" to "no_code", "error_description" to "CAS returned nothing"),
            authResultMap(AuthResult.Error("no_code", "CAS returned nothing")),
        )
        // No description from CAS falls back to the code, matching the other three bridges.
        assertEquals(
            mapOf("error" to "no_code", "error_description" to "no_code"),
            authResultMap(AuthResult.Error("no_code")),
        )
    }

    @Test
    fun `tokenMap sends the required fields and omits the absent optional ones`() {
        val minimal = KrdpassTokenResult(
            accessToken = "at",
            idToken = null,
            tokenType = "Bearer",
            expiresIn = 3600,
            refreshToken = null,
            scope = null,
        )
        assertEquals(
            mapOf("accessToken" to "at", "tokenType" to "Bearer", "expiresIn" to 3600),
            tokenMap(minimal),
        )

        val full = KrdpassTokenResult(
            accessToken = "at",
            idToken = "it",
            tokenType = "Bearer",
            expiresIn = 3600,
            refreshToken = "rt",
            scope = "openid profile",
        )
        assertEquals(
            mapOf(
                "accessToken" to "at",
                "tokenType" to "Bearer",
                "expiresIn" to 3600,
                "idToken" to "it",
                "refreshToken" to "rt",
                "scope" to "openid profile",
            ),
            tokenMap(full),
        )
    }

    @Test
    fun `userInfoMap always sends sub, upns and raw`() {
        val map = userInfoMap(KrdpassUserInfo(sub = "user-1"))

        assertEquals("user-1", map["sub"])
        assertEquals(emptyList<String>(), map["upns"])
        assertEquals(emptyMap<String, Any?>(), map["raw"])
        // An absent claim is omitted, not sent as null.
        assertFalse(map.containsKey("name"))
        assertFalse(map.containsKey("upn"))
    }

    @Test
    fun `userInfoMap sends every claim under its camelCase key`() {
        val map = userInfoMap(
            KrdpassUserInfo(
                sub = "user-1",
                name = "Aram Rashid",
                givenName = "Aram",
                familyName = "Rashid",
                picture = "https://example.krd/p.png",
                email = "aram@example.krd",
                citizenFirst = "Aram",
                citizenSecond = "Kamal",
                citizenThird = "Sabir",
                citizenSurname = "Rashid",
                citizenProfilePicture = "https://example.krd/c.png",
                birthdate = "1990-01-01",
                sexAtBirth = "male",
                upn = "1234567890",
                upns = listOf("0987654321"),
                did = "did:krd:abc",
            ),
        )

        assertEquals("Aram Rashid", map["name"])
        assertEquals("Aram", map["givenName"])
        assertEquals("Rashid", map["familyName"])
        assertEquals("https://example.krd/p.png", map["picture"])
        assertEquals("aram@example.krd", map["email"])
        assertEquals("Aram", map["citizenFirst"])
        assertEquals("Kamal", map["citizenSecond"])
        assertEquals("Sabir", map["citizenThird"])
        assertEquals("Rashid", map["citizenSurname"])
        assertEquals("https://example.krd/c.png", map["citizenProfilePicture"])
        assertEquals("1990-01-01", map["birthdate"])
        assertEquals("male", map["sexAtBirth"])
        assertEquals("1234567890", map["upn"])
        assertEquals(listOf("0987654321"), map["upns"])
        assertEquals("did:krd:abc", map["did"])
        // The Dart model derives the full name; the bridge must not send a second copy.
        assertFalse(map.containsKey("citizenFullName"))
    }

    @Test
    fun `sanitizeClaims turns dates into epoch seconds, nested too`() {
        val claims = sanitizeClaims(
            mapOf(
                "exp" to java.util.Date(1_700_000_000_000L),
                "sub" to "user-1",
                "nested" to mapOf("iat" to java.util.Date(1_699_000_000_000L)),
                "list" to listOf(java.util.Date(1_698_000_000_000L)),
            ),
        )

        assertEquals(1_700_000_000L, claims["exp"])
        assertEquals("user-1", claims["sub"])
        assertEquals(mapOf("iat" to 1_699_000_000L), claims["nested"])
        assertEquals(listOf(1_698_000_000L), claims["list"])
    }

    @Test
    fun `sanitizeClaims keeps a null claim`() {
        val claims = sanitizeClaims(mapOf("nonce" to null))
        assertTrue(claims.containsKey("nonce"))
        assertNull(claims["nonce"])
    }

    @Test
    fun `signInErrorMap forwards the structured code and message`() {
        val map = signInErrorMap(KrdpassError.Timeout())
        assertEquals("timeout", map["error"])
        assertEquals("Authentication timed out", map["error_description"])
    }

    @Test
    fun `signInErrorMap never sends a blank error_description`() {
        // A blank description renders as "Failed: " in an app displaying it verbatim.
        assertEquals("Authentication failed", signInErrorMap(RuntimeException())["error_description"])
        assertEquals("Authentication failed", signInErrorMap(RuntimeException("  "))["error_description"])
        assertEquals("authentication_failed", signInErrorMap(RuntimeException())["error"])
    }
}
