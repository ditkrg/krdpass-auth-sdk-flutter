# KRDPASS Auth SDK (Flutter)

Official Flutter plugin for **Sign in with KRDPASS**: app-to-app SSO with the KRDPASS
identity app (not a browser/WebView flow).

KRDPASS credentials are approval-based, not open self-service: onboarding contact is
`integration@pass.krd`, since integrations may access sensitive citizen identity data.
Keep `client_secret` and signing keys server-side, and use the server-mediated flow for
production.

## Requirements

- Flutter stable SDK (Dart ^3.9.0, Flutter >=3.35.0)
- Android `minSdk` 24+, iOS 15.5+
- A registered KRDPASS client (`clientId`, approved scopes, HTTPS `redirectUri`)
- Production and development environments are both supported (`KrdpassEnvironment.production` / `.development`)

## Install

Add the SDK as a git dependency on the release tag (no pub.dev publish):

```yaml
dependencies:
  krdpass_auth_flutter:
    git:
      url: https://github.com/ditkrg/krdpass-auth-sdk-flutter.git
      ref: v1.0.0
```

Then `flutter pub get`.

## Platform setup

### Android setup (required)

The Android half of this plugin depends on the core SDK `krd.pass:krdpass-auth`,
published to **Maven Central**. It resolves automatically via `mavenCentral()`, no
extra repository or credentials needed.

The app-to-app launch also needs **package visibility** on Android 11+. Add this as a
direct child of `<manifest>` in your app's `android/app/src/main/AndroidManifest.xml`:

```xml
<queries>
    <package android:name="krd.pass" />
    <package android:name="krd.pass.dev" />
</queries>
```

Without it, launching KRDPASS silently fails on Android 11+.

The plugin also requires the host Activity to be a `ComponentActivity`. With Flutter
that means declaring `MainActivity : FlutterFragmentActivity()`. The stock
`FlutterActivity` template is **not** supported: the plugin silently skips
registration and authentication calls will never complete. This mirrors the native
Android SDK's Activity-registration requirement (see the Android SDK's Platform setup).

### iOS setup (required)

For **iOS**, the plugin depends on the `KrdpassAuth` pod, which is not on the CocoaPods
trunk. Add its source to your app's `ios/Podfile` so `pod install` can resolve it:

```ruby
pod 'KrdpassAuth', :git => 'https://github.com/ditkrg/krdpass-auth-sdk-ios.git', :tag => 'v1.0.0'
```

The KRDPASS redirect returns to your app as a **Universal Link**, so your app must be
associated with the `redirectUri` host:

1. Enable the **Associated Domains** capability and add your redirect host to
   `ios/Runner/Runner.entitlements`:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
       <string>applinks:auth.your-app.example.com</string>
   </array>
   ```

2. The host in your `redirectUri` **must equal** that `applinks:` host, and that host
   must serve a valid `apple-app-site-association` file listing your app's `appID` and
   the redirect path.

3. If your app also uses Flutter's own routing/deep linking, set
   `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist` so Flutter's
   built-in handler doesn't consume the KRDPASS callback before the plugin's native
   handler receives it:

   ```xml
   <key>FlutterDeepLinkingEnabled</key>
   <false/>
   ```

## Quickstart

1. **Initialize** once at startup:

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

2. **Client-only sign-in (no backend)**: the SDK runs PKCE, PAR, and token exchange
   directly with KRDPASS and returns tokens:

   ```dart
   try {
     final tokens = await auth.signIn(scopes: ['openid', 'profile']);
     final userInfo = await auth.getUserInfo(accessToken: tokens.accessToken);
   } on KrdpassCancelledException {
     // usually no UI needed
   } on KrdpassTimeoutException {
     // offer retry
   } on KrdpassBusyException {
     // ignore or queue
   } on KrdpassNetworkException catch (e) {
     // safe to retry; e.cause has the underlying detail
   } on KrdpassAuthenticationException catch (e) {
     // e.code may be state_mismatch, provider_not_installed (e.installUrl set), etc.
   } on KrdpassException catch (e) {
     // fallback for any other SDK error
   }
   ```

3. **Server-mediated flow (recommended for production)**: your server performs PAR and
   the token exchange; the SDK only launches KRDPASS and returns the authorization code:

   ```dart
   final state = auth.generateState();
   // requestUri comes from your backend's PAR endpoint.
   final result = await auth.authenticate(requestUri: requestUri, state: state);
   if (result.isSuccess) {
     // Send result.code + result.state to your backend to exchange for tokens.
   } else if (result.isCancelled) {
     // usually no UI needed
   } else if (result.isTimeout) {
     // offer retry
   } else if (result.isBusy) {
     // ignore or queue
   } else if (result.isStateMismatch) {
     // fail closed and restart
   } else if (result.isProviderNotInstalled) {
     // result.installUrl is set, open it
   } else {
     // result.error / result.errorDescription
   }
   ```

Verify an ID token (signature via JWKS, audience, expiry):

```dart
final claims = await auth.verifyToken(idToken: tokens.idToken!);
```

> Helpers that do **not** verify a token are intentionally named
> `decodeTokenUnverified`. Never use their output for trust decisions.

## Error handling

| Code | Meaning | Typical handling |
| --- | --- | --- |
| `cancelled` | User cancelled in KRDPASS (`access_denied` / `user_cancelled` / `login_required` / `consent_denied` are classified as cancellation too) | Usually no UI needed |
| `access_denied` | User declined consent (classified as cancellation) | Usually no UI needed |
| `timeout` | Auth window elapsed | Offer retry |
| `busy` | Another authentication is in progress | Ignore or queue |
| `state_mismatch` | Returned state differs from expected (possible CSRF/response injection) | Fail closed and restart |
| `invalid_redirect` | Redirect URI does not match the configured host | Check onboarding config |
| `invalid_request` | Malformed or blank request parameters | Fix the integration |
| `request_expired` | The request_uri expired inside KRDPASS (NOT a cancellation) | Restart with a fresh PAR request |
| `launch_failed` | The KRDPASS app could not be launched | Retry or check installation |
| `provider_not_installed` | KRDPASS app not installed (`installUrl` is provided) | Open it |
| `no_code` | Provider returned no authorization code | Restart the flow |
| `network_error` | Network failure during token exchange | Safe to retry |
| `platform_error` | Platform-level failure such as an unregistered caller | Log and report |

The **client-only** `signIn` flow throws a `KrdpassException` subclass
(`KrdpassCancelledException`, `KrdpassTimeoutException`, `KrdpassBusyException`,
`KrdpassNetworkException`, or `KrdpassAuthenticationException`. The latter carries a
`code` such as `state_mismatch` or `provider_not_installed`, plus an optional
`installUrl`). The **server-mediated** `authenticate` flow returns an `AuthResult`
whose `isSuccess` / `isCancelled` / `isTimeout` / `isBusy` / `isStateMismatch` /
`isProviderNotInstalled` fields (plus `error` / `errorDescription` / `installUrl`) let
you branch without a `switch`.

## Refresh Token Policy

`refreshTokens` and `revokeToken` APIs are available for approved integrations, but refresh
token issuance is high-sensitivity and usually not enabled by default for early integrations.

## Required Onboarding Inputs

- `clientId`
- Approved scopes
- HTTPS `redirectUri`
- Android package/signing fingerprint and iOS associated-domain metadata

## Example App

A runnable Flutter demo of both the client-only and server-mediated flows is maintained
in the KRDPASS demos repository.

## Security Notes

- Keep `client_secret` and private keys server-side.
- Never commit secrets, keystores, or `.env` files.

## Backend & Protocol Reference

- Integration guide: <https://docs.digital.gov.krd/software-development/04-interoperability/11-krdpass-sign-in-with-krdpass.html>

## Development

```bash
flutter test
flutter analyze
```

## License

[MIT](LICENSE) (c) KRG-DTID.
