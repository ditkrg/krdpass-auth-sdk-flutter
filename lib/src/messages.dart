/// Canonical, user-safe error messages: the single home for the fixed-message
/// strings shared by the [KrdpassException] hierarchy and the [AuthResult] model.
/// Keep these byte-identical with the iOS/Android/RN SDKs (guarded by
/// test/messages_test.dart).
const kMsgCancelled = 'Authentication was cancelled';
const kMsgTimeout = 'Authentication timed out';
const kMsgBusy = 'Another authentication is already in progress';
