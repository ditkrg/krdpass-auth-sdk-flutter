# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1]

### Security

- Bumps the native iOS and Android SDKs to 1.0.1, which enforce strict OAuth
  `state` validation on authorization error responses.

## [1.0.0]

### Added

- Initial release of the KRDPASS Auth SDK for Flutter.
- Client-only flow (`signIn`) and server-mediated flow (`authenticate`), with the
  client-only sign-in window bounded by the PAR `request_uri` lifetime.
- PKCE and Pushed Authorization Request (PAR) support.
- JWKS-based ID-token verification (`verifyToken`), with `verifyToken(idToken:)`
  deriving the audience from the configured `clientId` (consistent with the
  Android and React Native SDKs).
- Token refresh, revoke, and userinfo helpers.
- The native Android core resolves from Maven Central (`krd.pass:krdpass-auth`),
  no token or extra repository needed.
