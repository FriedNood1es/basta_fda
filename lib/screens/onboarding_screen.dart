import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final FDAChecker fdaChecker;
  const OnboardingScreen({super.key, required this.fdaChecker});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;
  String? _error;
  bool _showWhy = false;

  Future<void> _begin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Request camera access by enumerating and initializing later in Scanner
      final cameras = await availableCameras();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(cameras: cameras, fdaChecker: widget.fdaChecker),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Camera access failed. Please grant permission in system settings and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
              theme.colorScheme.primary.withValues(alpha: 0.05),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Center(child: Image.asset('assets/logo.png', height: 96)),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome to bastaFDA',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Scan labels, verify FDA registration, and get quick guidance.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _ChipHint(icon: Icons.offline_bolt_rounded, label: 'Offline-friendly'),
                            _ChipHint(icon: Icons.verified_user_rounded, label: 'On-device text'),
                            _ChipHint(icon: Icons.cloud_off_rounded, label: 'No uploads unless you share'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _StepCard(
                          title: '1) Allow camera access',
                          body: 'We only use it to read the printed text on packaging. Nothing is sent unless you choose to share.',
                        ),
                        _StepCard(
                          title: '2) Capture label text',
                          body: 'Aim at the registration number and key product text. You can retake or edit before searching.',
                        ),
                        _StepCard(
                          title: '3) Review results',
                          body: 'See registration status and packaging helper cues when available. You stay in control.',
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _showWhy = !_showWhy),
                          icon: Icon(_showWhy ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                          label: const Text('Why we ask for camera permission'),
                        ),
                        if (_showWhy)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'We only access the camera to read text on packaging. Processing stays on-device. '
                              'You can revoke permission anytime in system settings.',
                            ),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Tip: If you denied permission permanently, open Settings > Apps > bastaFDA > Permissions > Camera and switch to Allow. Then tap Try Again.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _begin,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _begin,
                    icon: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(_loading ? 'Requesting permission…' : 'Start Scanning'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipHint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16, color: theme.colorScheme.primary),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: theme.colorScheme.surfaceVariant.withValues(alpha: 0.6),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String title;
  final String body;
  const _StepCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
