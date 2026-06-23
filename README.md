# KRDPASS Auth SDK (Flutter)

Official Flutter plugin for **Sign in with KRDPASS** — app-to-app SSO with the KRDPASS
identity app (not a browser/WebView flow).

## Requirements

- Flutter stable SDK (Dart 3+)
- Android `minSdk` 24+, iOS 15+
- A registered KRDPASS client (`clientId`, approved scopes, HTTPS `redirectUri`)

## Install

Add the SDK as a git dependency on the release tag (no pub.dev publish):

```yaml
dependencies:
  krdpass_auth_flutter:
    git:
      url: https://github.com/ditkrg/krdpass-auth-sdk-flutter.git
      ref: v1.0.0
```

Then `flutter pub get`. Access to the private repo (SSH key or token) is required.

### Android setup (required)

The Android half of this plugin depends on the core SDK
`krd.pass:krdpass-auth`, published privately to **GitHub Packages**. Your app's
Gradle build must declare that Maven repository with a token that has the
`read:packages` scope, or the Android build will fail to resolve the artifact.

In your app's `android/settings.gradle.kts` (or `build.gradle`), under
`dependencyResolutionManagement { repositories { ... } }`:

```kotlin
maven {
    url = uri("https://maven.pkg.github.com/ditkrg/krdpass-auth-sdk-android")
    credentials {
        username = providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")
        password = providers.gradleProperty("gpr.token").orNull ?: System.getenv("GITHUB_TOKEN")
    }
}
```

Provide the credentials via `~/.gradle/gradle.properties` (`gpr.user` /
`gpr.token`) or the `GITHUB_ACTOR` / `GITHUB_TOKEN` environment variables. iOS
needs no extra setup (the pod is vendored through the plugin).

## Quickstart

Initialize once at startup:

```dart
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

final auth = KrdpassAuth.instance;
await auth.initialize(
  config: const KrdpassConfig(
    clientId: 'your-client-id',
    redirectUri: 'https://auth.your-app.example.com/callback',
    environment: KrdpassEnvironment.production,
  ),
);
```

**Client-only flow** (`signIn`) — the SDK runs PKCE, PAR, and token exchange directly
with KRDPASS and returns tokens. No backend required:

```dart
final tokens = await auth.signIn(scopes: ['openid', 'profile']);
final userInfo = await auth.getUserInfo(accessToken: tokens.accessToken);
```

**Backend-mediated flow** (`authenticate`) — your server performs PAR and the token
exchange; the SDK only launches KRDPASS and returns the authorization code:

```dart
final state = auth.generateState();
// requestUri comes from your backend's PAR endpoint.
final result = await auth.authenticate(requestUri: requestUri, state: state);
// Send result.code + state to your backend to exchange for tokens.
```

Verify an ID token (signature via JWKS, issuer, audience, expiry):

```dart
final claims = await auth.verifyToken(token: tokens.idToken!);
```

> Helpers that do **not** verify a token are intentionally named
> `decodeTokenUnverified` — never use their output for trust decisions.

## Integration Notes

- iOS callback completion uses Universal Links (`https://`); the KRDPASS app must be installed.
- Android callback completion uses the Activity/Intent result from the explicit KRDPASS launch.
- Recommended production flow is the server-mediated `authenticate` path.

## Required Onboarding Inputs

- `clientId`
- Approved scopes
- HTTPS `redirectUri`
- Android package/signing fingerprint and iOS associated-domain metadata

## Example App

A runnable demo of both flows lives in [`example/`](example/) — see
[`example/README.md`](example/README.md) for setup.

## Security Notes

- Keep `client_secret` and private keys server-side.
- Never commit secrets, keystores, or `.env` files.

## Backend & Protocol Reference

- Integration guide: <https://docs.digital.gov.krd/software-development/04-interoperability/11-krdpass-sign-in-with-krdpass.html>
