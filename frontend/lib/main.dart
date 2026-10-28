import 'package:flutter/material.dart';

import 'api.dart';
import 'notifications.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocketWiseApp());
}

class PocketWiseApp extends StatefulWidget {
  const PocketWiseApp({super.key});

  @override
  State<PocketWiseApp> createState() => _PocketWiseAppState();
}

class _PocketWiseAppState extends State<PocketWiseApp> {
  final Api api = Api();

  bool loading = true;
  bool signedIn = false;
  String? startupError;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    setState(() {
      loading = true;
      startupError = null;
    });

    try {
      // Notification initialization handles unsupported platforms internally.
      await Notifications.initialize();

      final restored = await api.restoreSession();

      if (!mounted) return;

      setState(() {
        signedIn = restored;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        startupError = readableError(error);
        loading = false;
      });
    }
  }

  void enterApp() {
    setState(() => signedIn = true);
  }

  void leaveApp() {
    setState(() => signedIn = false);
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketWise',
      debugShowCheckedModeBanner: false,
      theme: pocketWiseTheme(),
      home: loading
          ? const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 64,
                      color: brandColor,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'PocketWise',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            )
          : startupError != null
              ? Scaffold(
                  body: ErrorMessage(
                    message: startupError!,
                    onRetry: initialize,
                  ),
                )
              : signedIn
                  ? HomeScreen(
                      api: api,
                      onSignedOut: leaveApp,
                    )
                  : AuthScreen(
                      api: api,
                      onAuthenticated: enterApp,
                    ),
    );
  }
}