/// Canonical, user-safe error messages. Keep these byte-identical with the
/// iOS/Android/RN SDKs (guarded by test/messages_test.dart); the full set is
/// declared so the parity test locks the strings the native cores return over
/// the channel too, not only the ones Flutter constructs locally.
const kMsgCancelled = 'Authentication was cancelled';
const kMsgTimeout = 'Authentication timed out';
const kMsgBusy = 'Another authentication is already in progress';
const kMsgProviderNotInstalled =
    'The KRDPASS app is not installed or could not be opened. Please install or update KRDPASS.';
const kMsgStateMismatch =
    'State parameter mismatch: possible CSRF or response injection';
const kMsgIssuerMismatch =
    'Issuer mismatch: the response did not come from the expected authorization server';
const kMsgNoCode = 'No authorization code received';
const kMsgInvalidRedirect =
    'Redirect URI does not match the exact configured endpoint';
const kMsgStateRequired =
    "state is required and cannot be blank. Pass the state returned by your backend's PAR call, or use signIn().";
const kMsgMissingIdToken = 'Token response did not include an id_token';
const kMsgNonceMismatch = 'ID token nonce mismatch (possible token replay)';
