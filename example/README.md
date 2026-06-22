# KRDPASS Flutter Example App

Reference Flutter app for **Sign in with KRDPASS**.

## What This Example Demonstrates

- Server-mediated OAuth flow
- PAR + PKCE integration
- iOS Universal Link and Android Intent callback behavior

## Prerequisites

- Flutter stable SDK
- KRDPASS app on test device/emulator
- HTTPS domain/tunnel for callback URL
- A running backend that performs PAR + token exchange (see the integration guide linked below)

## Required Onboarding Inputs

- `CLIENT_ID`
- `REDIRECT_URI` (HTTPS)
- `BACKEND_URL`
- CAS base URLs for your environment
- iOS associated domain and Android app identity metadata registered with KRDPASS

## Step-by-Step Setup

1. (Optional) create local `.env` from template:

```bash
cp env.example .env
```

2. Edit `.env` values:

```env
CLIENT_ID=your-client-id
REDIRECT_URI=https://auth.your-app.example.com/_krdpass/oauth/callback
BACKEND_URL=https://api.your-backend.example.com
CAS_AUTH_SERVER_URL=https://auth.dev.krd
CAS_TOKEN_URL=https://auth.dev.krd/connect/token
CAS_PAR_URL=https://auth.dev.krd/connect/par
```

3. Stand up a backend that implements PAR + token exchange (see the integration guide
   in Related Docs). Point `BACKEND_URL` at it.

4. Run the Flutter example:

```bash
flutter pub get
flutter run
```

## Notes

- Keep `client_secret` and private keys on backend only.
- Use your app's Universal Link host for `REDIRECT_URI` (iOS Associated Domains).
- Keep the redirect URI HTTPS and exactly matched to onboarding registration.

## Related Docs

- SDK README: [`../README.md`](../README.md)
- Integration guide: <https://docs.digital.gov.krd/software-development/04-interoperability/11-krdpass-sign-in-with-krdpass.html>
