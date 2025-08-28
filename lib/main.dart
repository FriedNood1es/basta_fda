import 'package:flutter/material.dart';
import 'services/fda_checker.dart';
import 'services/settings_service.dart';
import 'package:camera/camera.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scanner_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FDA Checker and load CSV
  final fdaChecker = FDAChecker();
  // Kick off background loading; UI will react when ready
  // (Scanner disables Confirm until data is loaded)
  // ignore: discarded_futures
  fdaChecker.loadCSV();

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
      Widget target;
      if (!s.hasSeenWelcome) {
        target = WelcomeScreen(fdaChecker: widget.fdaChecker);
      } else if (s.isLoggedIn || s.guestMode) {
        target = ScannerScreen(cameras: cameras, fdaChecker: widget.fdaChecker);
      } else {
        target = LoginScreen(cameras: cameras, fdaChecker: widget.fdaChecker);
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => target),
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
