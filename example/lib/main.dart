import 'package:flutter/material.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

// Replace with the clientId and redirectUri issued to your integration; the
// flow cannot complete against placeholders. See the README for platform setup.
const _clientId = 'your-client-id';
const _redirectUri = 'https://auth.your-app.example.com/callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KrdpassAuth.instance.initialize(
    config: const KrdpassConfig(clientId: _clientId, redirectUri: _redirectUri),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'KRDPASS Auth example',
      home: SignInScreen(),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with WidgetsBindingObserver {
  final _auth = KrdpassAuth.instance;
  String _status = 'Not signed in';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning mid-flow means the user abandoned KRDPASS; free the SDK for a retry.
    if (state == AppLifecycleState.resumed && _busy) {
      _auth.cancelPendingAuthentication();
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _status = 'Signing in...';
    });

    var status = 'Failed';
    try {
      final tokens = await _auth.signIn();
      final user = await _auth.getUserInfo(accessToken: tokens.accessToken);
      status = 'Signed in as ${user.name ?? user.sub}';
    } on KrdpassCancelledException {
      status = 'Cancelled';
    } on KrdpassException catch (e) {
      status = 'Failed: ${e.message}';
    } catch (e) {
      status = 'Failed: $e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = status;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with KRDPASS')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_status, textAlign: TextAlign.center),
            ),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
