## 1.0.0

* Initial release of the KRDPASS Auth SDK.
* `verifyToken` now takes `idToken` (was `token`) and derives the audience from the
  configured `clientId`, matching the Android/React Native SDKs.
