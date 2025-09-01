import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scanner_screen.dart';
import 'package:basta_fda/services/settings_service.dart';

class LoginScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  const LoginScreen({super.key, required this.cameras, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(0.03),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          Image.asset('assets/logo.png', height: 64),
                          const SizedBox(height: 8),
                          Text('Welcome back', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Sign in to continue', style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final s = SettingsService.instance;
                            await s.load();
                            s.isLoggedIn = true; // mock email login
                            s.guestMode = false;
                            s.authProvider = 'email';
                            await s.save();
                            if (!context.mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ScannerScreen(cameras: cameras, fdaChecker: fdaChecker),
                              ),
                            );
                          },
                          child: const Text('Login'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            // Placeholder for Google Sign-In integration
                            final s = SettingsService.instance;
                            await s.load();
                            s.isLoggedIn = true;
                            s.guestMode = false;
                            s.authProvider = 'google';
                            await s.save();
                            if (!context.mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => ScannerScreen(cameras: cameras, fdaChecker: fdaChecker)),
                            );
                          },
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                          label: const Text('Continue with Google'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => RegisterScreen(cameras: cameras, fdaChecker: fdaChecker)),
                              );
                            },
                            child: const Text('Create account'),
                          ),
                          const SizedBox(width: 6),
                          const Text('•'),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () async {
                              final s = SettingsService.instance;
                              await s.load();
                              s.guestMode = true; // remember guest session
                              s.isLoggedIn = false;
                              await s.save();
                              if (!context.mounted) return;
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScannerScreen(cameras: cameras, fdaChecker: fdaChecker),
                                ),
                              );
                            },
                            child: const Text('Skip for now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  const RegisterScreen({super.key, required this.cameras, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Image.asset('assets/logo.png', height: 64),
                        const SizedBox(height: 8),
                        Text('Join bastaFDA', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final s = SettingsService.instance;
                          await s.load();
                          s.isLoggedIn = true;
                          s.guestMode = false;
                          s.authProvider = 'email';
                          await s.save();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => ScannerScreen(cameras: cameras, fdaChecker: fdaChecker)),
                            (route) => false,
                          );
                        },
                        child: const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final s = SettingsService.instance;
                          await s.load();
                          s.isLoggedIn = true;
                          s.guestMode = false;
                          s.authProvider = 'google';
                          await s.save();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => ScannerScreen(cameras: cameras, fdaChecker: fdaChecker)),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                        label: const Text('Sign up with Google'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to sign in'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

