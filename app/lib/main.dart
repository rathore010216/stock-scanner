import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_web_options.dart';
import 'widgets/responsive.dart' show kWideBreakpoint;
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    if (!webFirebaseConfigured) {
      runApp(const _WebConfigMissing());
      return;
    }
    await Firebase.initializeApp(options: webFirebaseOptions);
  } else {
    // Android reads google-services.json.
    await Firebase.initializeApp();
  }
  // Best-effort: set up local notifications (SL/target alerts). No-op on web.
  try {
    await NotificationService.instance.init();
  } catch (_) {}
  runApp(const StockApp());
}

/// Shown only if the web build was made without the Firebase web config.
class _WebConfigMissing extends StatelessWidget {
  const _WebConfigMissing();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Web build is missing its Firebase settings.\n\n'
                'Add the FIREBASE_WEB_CONFIG secret in GitHub and re-run '
                'the "Build web app" workflow.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NSE Swing Screener',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
      ),
      // Web: wide windows get the desktop layout (HomeShell); narrower ones
      // keep the phone layout, centred and capped so it stays readable.
      // Phones are unaffected.
      builder: (context, child) => !kIsWeb ||
              MediaQuery.sizeOf(context).width >= kWideBreakpoint
          ? child!
          : ColoredBox(
              color: Colors.grey.shade200,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: child,
                ),
              ),
            ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
