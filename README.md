# KRDPASS Auth SDK (Flutter)

Official Flutter plugin for **Sign in with KRDPASS**.

## Requirements

- Flutter stable SDK
- Android/iOS platform setup for KRDPASS callback behavior

## Install from This Repository (v1)

1. Clone the SDK repo:

```bash
git clone https://github.com/ditkrg/krdpass-auth-sdk.git
```

2. Add local path dependency in your app `pubspec.yaml`:

```yaml
dependencies:
  krdpass_auth_flutter:
    path: ../krdpass-auth-sdk/packages/krdpass_auth_flutter
```

3. Install dependencies:

```bash
flutter pub get
```

## Optional Git Dependency

```yaml
dependencies:
  krdpass_auth_flutter:
    git:
      url: https://github.com/ditkrg/krdpass-auth-sdk.git
      path: packages/krdpass_auth_flutter
      ref: main
```

## Integration Notes

- iOS callback completion uses Universal Links (`https://`).
- Android callback completion uses Activity/Intent result.
- Recommended production flow is server-mediated OAuth.

## Required Onboarding Inputs

- `clientId`
- Approved scopes
- HTTPS `redirectUri`
- Android package/signing fingerprint and iOS associated domain metadata

## Example App

- Path: `packages/krdpass_auth_flutter/example`
- Setup guide: `packages/krdpass_auth_flutter/example/README.md`

## Security Notes

- Keep `client_secret` and private keys server-side.
- Never commit secrets, keystores, or `.env` files.

## Related Docs

- Root guide: `../../README.md`
- Integration architecture: `../../docs/INTEGRATION.md`
- Server reference: `../../examples/server/README.md`
