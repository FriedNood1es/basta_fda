import 'package:flutter/material.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/onboarding_screen.dart';
import 'package:basta_fda/services/settings_service.dart';

class WelcomeScreen extends StatelessWidget {
  final FDAChecker fdaChecker;
  const WelcomeScreen({super.key, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(child: Image.asset('assets/logo.png', height: 132)),
                const SizedBox(height: 24),
                Text(
                  'Welcome to bastaFDA',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your first defense against fake medicines.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                  onPressed: () async {
                    // Mark welcome as seen so subsequent launches skip this screen
                    final s = SettingsService.instance;
                    await s.load();
                    s.hasSeenWelcome = true;
                    await s.save();
                    if (!context.mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OnboardingScreen(fdaChecker: fdaChecker),
                      ),
                    );
                  },
                    child: const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
