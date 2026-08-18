# KRDPASS Auth SDK (Flutter)

Sign in with KRDPASS for Flutter apps. The plugin wraps the native Android and iOS cores,
which hand off to the installed KRDPASS identity app. It is not a browser or WebView flow.

Full integration guide, onboarding, error codes and security requirements:
**[KRDPASS documentation](https://docs.digital.gov.krd/software-development/04-interoperability/11-krdpass-sign-in-with-krdpass.html)**

## What this package is, and is not

This package is a thin method-channel bridge. None of the security-critical protocol code
lives here. PKCE, nonce generation and binding, exact-match redirect URI validation, the ID
token signature check, the `iss` / `aud` / `exp` claim checks and JWKS handling are all in
the native cores:

- Android: [`krd.pass:krdpass-auth`](https://github.com/ditkrg/krdpass-auth-sdk-android)
- iOS: [`KrdpassAuth`](https://github.com/ditkrg/krdpass-auth-sdk-ios)

What this package does own: launching the flow, marshalling arguments and results across the
method channel, validating the returned `state` against the one you passed, mapping native
error codes to the typed exception hierarchy, and parsing the token and user info payloads.
Auditing this repository is not the same as auditing the KRDPASS sign-in flow.

## Requirements

- Dart 3.12, Flutter 3.44 or newer
- Android `minSdk` 24, iOS 15.0
- A `clientId`, approved scopes, and an HTTPS `redirectUri`. See
  [Getting started](https://docs.digital.gov.krd/software-development/04-interoperability/12-krdpass-getting-started.html).

## Install

Not published on pub.dev. Depend on the release tag:

```yaml
dependencies:
  krdpass_auth_flutter:
    git:
      url: https://github.com/ditkrg/krdpass-auth-sdk-flutter.git
      ref: v1.6.0
```

## Platform setup

Both platforms need setup. Skipping either produces a flow that launches and never returns.

### Android

**Your `MainActivity` must extend `FlutterFragmentActivity`**, not the stock
`FlutterActivity`. The plugin needs a `ComponentActivity` to receive the launch result; with
the stock template it silently skips registration and sign-in never completes.

```kotlin
class MainActivity : FlutterFragmentActivity()
```

**Declare package visibility** in `android/app/src/main/AndroidManifest.xml`, as a direct
child of `<manifest>`. Without it, launching KRDPASS silently fails on Android 11+:

```xml
<queries>
    <package android:name="krd.pass" />
    <package android:name="krd.pass.dev" />
</queries>
```

The plugin depends on the core as `krd.pass:krdpass-auth:1.6.0`, resolved from the
repositories your app already declares. Add `mavenCentral()` if it is not there.

**Declare a Kotlin Gradle plugin of 2.2.20 or newer** in `android/settings.gradle.kts`.
AGP 9 bundles Kotlin 2.2.10, which current Flutter rejects:

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}
```

Omit that pin and the Android build fails with "Your project's Kotlin version (2.2.10)
is lower than Flutter's minimum supported version of 2.2.20." In `android/app/build.gradle.kts`,
write the AGP id as `com.android.applic\u0061tion` rather than the literal string:
Flutter 3.44 scans that block as text and injects legacy KGP when it sees
`com.android.application`, which undoes the pin.

**Add-to-app hosts**: the plugin registers its activity-result launcher when the engine
attaches to the activity, and Android refuses that registration once the activity has
passed `onStart`. Attach the Flutter engine before then (for example from `onCreate`), or
sign-in cannot launch. The plugin logs an explicit error instead of crashing your host.

The `INTERNET` permission is declared by the plugin's own manifest and merges into your
app, so you do not need to add it.

### iOS

The redirect returns as a Universal Link, so your app must be associated with the
`redirectUri` host.

**1. Add the Associated Domains capability** and your redirect host to
`ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:auth.your-app.example.com</string>
</array>
```

The host must equal your `redirectUri` host, and must serve an
`apple-app-site-association` file listing your app's `appID` and the redirect path.

**2. If your app uses Flutter's own deep linking**, disable it in `ios/Runner/Info.plist`,
or Flutter consumes the KRDPASS callback before the plugin sees it:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

**3. Dependency resolution.** Swift Package Manager is the supported path and the Flutter
3.44 default: `Package.swift` pins the core, so there is nothing to do.

CocoaPods still works, but `KrdpassAuth` is not on the CocoaPods trunk (which goes
read-only on 2 December 2026 anyway), so you have to name the source yourself in your app's
`ios/Podfile`:

```ruby
pod 'KrdpassAuth', :git => 'https://github.com/ditkrg/krdpass-auth-sdk-ios.git', :tag => 'v1.6.0'
```

## Quickstart

**1. Initialize once**, at app start:

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

`initialize` is all a cold start needs: with a refresh token from secure storage you can call
`refreshTokens` (or `revokeToken`, `getUserInfo`, `verifyToken`) on a fresh process without
signing in again.

**2. Sign in.** Your backend runs PAR and the token exchange; the SDK launches KRDPASS and
returns the authorization code. PKCE and `state` are yours: generate both in the app, send
only the `codeChallenge` and the `state` to your backend, and hold the `codeVerifier` until
the exchange. Pass that same `state` back into `authenticate`, or the SDK fails closed with
`invalid_request`.

```dart
final pkce = auth.generatePkcePair();
final state = auth.generateState();

// Your backend runs the PAR with pkce.codeChallenge and state, and returns the request_uri.
final requestUri = await yourBackend.getRequestUri(
  codeChallenge: pkce.codeChallenge,
  state: state,
);

final result = await auth.authenticate(requestUri: requestUri, state: state);
if (result.isSuccess) {
  // send result.code + pkce.codeVerifier + result.state to your backend
} else if (result.isCancelled) {
  // usually no UI needed
} else if (result.isTimeout) {
  // offer retry
} else if (result.isBusy) {
  // ignore or queue
} else {
  // result.error, result.errorDescription, result.installUrl
}
```

The client-only `signIn` API ships but needs a public client, which is not currently issued
to any integration. Use the flow above.

### Recovering an abandoned flow

The most common real-world failure in app-to-app sign-in is the user switching back to your
app without finishing in KRDPASS. Nothing arrives in that case, so the flow sits pending
until its timeout; a retry in the meantime reports `busy`. Call
`cancelPendingAuthentication()` when your app returns to the foreground mid-flow:

```dart
await auth.cancelPendingAuthentication();
```

`dispose()` exists for tests and add-to-app teardown. It shuts the whole client down for
the process, so do not call it from a widget's `dispose` in a normal app.

### Logging

Nothing is logged until you install a log function. Tokens, authorization codes and PKCE
values are redacted before they reach it.

```dart
KrdpassLogger.logFunction = (level, message, [error, stackTrace]) =>
    debugPrint('[$level] $message');
```

## Error handling

Every error code, what emits it, and how to handle it:
[Testing and go-live](https://docs.digital.gov.krd/software-development/04-interoperability/14-krdpass-testing-and-go-live.html).

Codes arrive as typed exceptions from `signIn` and as `AuthResult` fields from
`authenticate`. `invalid_redirect` is Android-only: on iOS the same mismatch ends the flow as
`cancelled`.

## Tokens and identity

`getUserInfo`, `refreshTokens`, `revokeToken`, `verifyToken` and `decodeTokenUnverified` are
methods on `KrdpassAuth.instance`. Scopes, claims and token handling rules:
[Reference](https://docs.digital.gov.krd/software-development/04-interoperability/15-krdpass-reference.html).

The SDK never persists tokens. Storage requirements:
[Token storage](https://github.com/ditkrg/krdpass-auth-samples/blob/main/docs/TOKEN-STORAGE.md).

## Samples

Runnable apps for all five platforms, plus a reference backend:
[krdpass-auth-samples](https://github.com/ditkrg/krdpass-auth-samples).

## Development

```bash
flutter analyze
flutter test
```

## License

MIT. See [LICENSE](LICENSE).
