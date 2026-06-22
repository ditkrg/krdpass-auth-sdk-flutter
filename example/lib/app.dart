import 'package:demo_krdpass_auth/screens/login_screen.dart';
import 'package:demo_krdpass_auth/theme.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KRDPass Demo - Sign in with KRDPass',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const LoginScreen(),
    );
  }
}
