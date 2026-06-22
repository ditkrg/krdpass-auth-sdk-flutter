import 'package:demo_krdpass_auth/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // Keep the demo buildable out of the box with template values.
    await dotenv.load(fileName: "env.example");
  }

  KrdpassLogger.logFunction = (level, message, [error, stackTrace]) {
    final parts = <Object?>[message, error, stackTrace]
      ..removeWhere((part) => part == null);
    debugPrint('KRDPass $level: ${parts.join(' | ')}');
  };

  // Initialize the SDK once at startup
  final config = KrdpassConfig(
    environment: KrdpassEnvironment.development,
    clientId: dotenv.get('CLIENT_ID'),
    redirectUri: dotenv.get('REDIRECT_URI'),
  );

  await KrdpassAuth.instance.initialize(config: config);

  runApp(const App());
}
