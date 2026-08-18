// Compile guard for the code samples in README.md: if an example stops matching
// the public API, `flutter analyze` fails.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

Future<void> quickstartInitialize() async {
  final auth = KrdpassAuth.instance;
  await auth.initialize(
    config: const KrdpassConfig(
      clientId: 'your-client-id',
      redirectUri: 'https://auth.your-app.example.com/callback',
      // ignore: avoid_redundant_argument_values  README shows it explicitly
      environment: KrdpassEnvironment.production,
    ),
  );
}

Future<void> recoveringAnAbandonedFlow(KrdpassAuth auth) async {
  await auth.cancelPendingAuthentication();
}

Future<void> quickstartClientOnly(KrdpassAuth auth) async {
  try {
    final tokens = await auth.signIn(
      scopes: [KrdpassScopes.openid, KrdpassScopes.profile],
    );
    final userInfo = await auth.getUserInfo(accessToken: tokens.accessToken);
    debugPrint(userInfo.sub);
  } on KrdpassCancelledException {
    // usually no UI needed
  } on KrdpassTimeoutException {
    // offer retry
  } on KrdpassBusyException {
    // ignore or queue
  } on KrdpassNetworkException catch (e) {
    debugPrint('${e.cause}');
  } on KrdpassAuthenticationException catch (e) {
    debugPrint('${e.code} ${e.installUrl}');
  }
}

Future<void> quickstartServerMediated(
  KrdpassAuth auth,
  String requestUri,
  String state,
) async {
  final result = await auth.authenticate(requestUri: requestUri, state: state);
  if (result.isSuccess) {
    debugPrint('${result.code} ${result.state}');
  } else if (result.isCancelled) {
    // usually no UI needed
  } else if (result.isTimeout) {
    // offer retry
  } else if (result.isBusy) {
    // ignore or queue
  } else {
    debugPrint(
      '${result.error} ${result.errorDescription} ${result.installUrl}',
    );
  }
}

void quickstartLogging() {
  KrdpassLogger.logFunction = (level, message, [error, stackTrace]) =>
      debugPrint('[$level] $message');
}

void main() {
  test('README samples compile and quickstartLogging wires a log function', () {
    quickstartLogging();
    expect(KrdpassLogger.logFunction, isNotNull);
  });
}
