import 'package:flutter/material.dart';
import 'services/fda_checker.dart';
import 'services/settings_service.dart';
import 'package:camera/camera.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scanner_screen.dart';
import 'theme/app_theme.dart';
import 'services/firebase_bootstrap.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort Firebase init (safe no-op if not configured)
  await tryInitFirebase();

  // Initialize FDA Checker and load CSV
  final fdaChecker = FDAChecker();
  // Kick off cache-first load and freshness check; UI disables actions until ready
  // ignore: discarded_futures
  fdaChecker.ensureLoadedAndFresh();

  runApp(BastaFDAApp(fdaChecker: fdaChecker));
}

class BastaFDAApp extends StatelessWidget {
  final FDAChecker fdaChecker;

  const BastaFDAApp({super.key, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'bastaFDA',
      theme: AppTheme.light(),
      home: _StartRouter(fdaChecker: fdaChecker),
    );
  }
}

class _AuthRouter extends StatelessWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  const _AuthRouter({required this.cameras, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    // Guest mode short-circuit
    if (s.guestMode) {
      return ScannerScreen(cameras: cameras, fdaChecker: fdaChecker);
    }
    // If Firebase isn't initialized, fall back to Settings flags
    if (Firebase.apps.isEmpty) {
      final loggedIn = s.isLoggedIn;
      return loggedIn
          ? ScannerScreen(cameras: cameras, fdaChecker: fdaChecker)
          : LoginScreen(cameras: cameras, fdaChecker: fdaChecker);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user != null) {
          return ScannerScreen(cameras: cameras, fdaChecker: fdaChecker);
        }
        return LoginScreen(cameras: cameras, fdaChecker: fdaChecker);
      },
    );
  }
}

class _StartRouter extends StatefulWidget {
  final FDAChecker fdaChecker;
  const _StartRouter({required this.fdaChecker});

  @override
  State<_StartRouter> createState() => _StartRouterState();
}

class _StartRouterState extends State<_StartRouter> {
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    _route();
  }
  Future<void> _route() async {
    if (_routing) return;
    _routing = true;
    try {
      await SettingsService.instance.load();
      final cameras = await availableCameras();
      if (!mounted) return;

      final s = SettingsService.instance;
      if (!s.hasSeenWelcome) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => WelcomeScreen(fdaChecker: widget.fdaChecker)),
        );
        return;
      }

      // Route via Firebase Auth state when available. Guest mode overrides and
      // goes straight to Scanner for offline-first behavior.
      Widget gate = _AuthRouter(
        cameras: cameras,
        fdaChecker: widget.fdaChecker,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => gate),
      );
    } catch (_) {
      // If anything fails, fall back to Welcome
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WelcomeScreen(fdaChecker: widget.fdaChecker)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Simple splash while deciding where to go
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
