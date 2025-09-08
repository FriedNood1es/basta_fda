import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scanner_screen.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:basta_fda/services/auth_service.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  const LoginScreen({
    super.key,
    required this.cameras,
    required this.fdaChecker,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Sign In')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.03),
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
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            Image.asset('assets/logo.png', height: 64),
                            const SizedBox(height: 8),
                            Text(
                              'Welcome back',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your first defense against fake medicines.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _email,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.mail_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    final (ok, err) = await AuthService.instance
                                        .signInWithEmailPassword(
                                          _email.text.trim(),
                                          _password.text,
                                        );
                                    setState(() => _busy = false);
                                    if (!mounted) return;
                                    if (!ok) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(err ?? 'Login failed'),
                                        ),
                                      );
                                      return;
                                    }
                                    final s = SettingsService.instance;
                                    await s.load();
                                    s.isLoggedIn = true;
                                    s.guestMode = false;
                                    s.authProvider = 'email';
                                    final u = FirebaseAuth.instance.currentUser;
                                    if (u != null) {
                                      s.userEmail = u.email;
                                      s.displayName = u.displayName;
                                      await HistoryService.instance
                                          .switchProfileKey(u.uid);
                                    }
                                    await s.save();
                                    // Give the user immediate success feedback
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Logged in successfully'),
                                      ),
                                    );
                                    await Future.delayed(
                                      const Duration(milliseconds: 500),
                                    );
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ScannerScreen(
                                          cameras: widget.cameras,
                                          fdaChecker: widget.fdaChecker,
                                        ),
                                      ),
                                    );
                                  },
                            child: _busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Login'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    final (ok, err) = await AuthService.instance
                                        .signInWithGoogle();
                                    setState(() => _busy = false);
                                    if (!mounted) return;
                                    if (!ok) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            err ?? 'Google sign-in failed',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final s = SettingsService.instance;
                                    await s.load();
                                    s.isLoggedIn = true;
                                    s.guestMode = false;
                                    s.authProvider = 'google';
                                    await s.save();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Signed in with Google'),
                                      ),
                                    );
                                    await Future.delayed(
                                      const Duration(milliseconds: 500),
                                    );
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ScannerScreen(
                                          cameras: widget.cameras,
                                          fdaChecker: widget.fdaChecker,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 28,
                            ),
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
                                  MaterialPageRoute(
                                    builder: (_) => RegisterScreen(
                                      cameras: widget.cameras,
                                      fdaChecker: widget.fdaChecker,
                                    ),
                                  ),
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
                                // Use guest history profile for this session
                                await HistoryService.instance.switchProfileKey(
                                  'guest',
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Continuing as guest'),
                                  ),
                                );
                                await Future.delayed(
                                  const Duration(milliseconds: 450),
                                );
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ScannerScreen(
                                      cameras: widget.cameras,
                                      fdaChecker: widget.fdaChecker,
                                    ),
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
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  const RegisterScreen({
    super.key,
    required this.cameras,
    required this.fdaChecker,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

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
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          Image.asset('assets/logo.png', height: 64),
                          const SizedBox(height: 8),
                          Text(
                            'Join bastaFDA',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your first defense against fake medicines.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _name,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _email,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.mail_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _password,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  final (ok, err) = await AuthService.instance
                                      .registerWithEmailPassword(
                                        _email.text.trim(),
                                        _password.text,
                                        displayName: _name.text.trim(),
                                      );
                                  setState(() => _busy = false);
                                  if (!mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          err ?? 'Registration failed',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final s = SettingsService.instance;
                                  await s.load();
                                  s.isLoggedIn = true;
                                  s.guestMode = false;
                                  s.authProvider = 'email';
                                  final u = FirebaseAuth.instance.currentUser;
                                  if (u != null) {
                                    s.userEmail = u.email;
                                    s.displayName = u.displayName;
                                    await HistoryService.instance
                                        .switchProfileKey(u.uid);
                                  }
                                  await s.save();
                                  // Show success before navigating
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Account created'),
                                    ),
                                  );
                                  await Future.delayed(
                                    const Duration(milliseconds: 600),
                                  );
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ScannerScreen(
                                        cameras: widget.cameras,
                                        fdaChecker: widget.fdaChecker,
                                      ),
                                    ),
                                    (route) => false,
                                  );
                                },
                          child: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create account'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  final (ok, err) = await AuthService.instance
                                      .signInWithGoogle();
                                  setState(() => _busy = false);
                                  if (!mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          err ?? 'Google sign-in failed',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final s = SettingsService.instance;
                                  await s.load();
                                  s.isLoggedIn = true;
                                  s.guestMode = false;
                                  s.authProvider = 'google';
                                  final u = FirebaseAuth.instance.currentUser;
                                  if (u != null) {
                                    s.userEmail = u.email;
                                    s.displayName = u.displayName;
                                    await HistoryService.instance
                                        .switchProfileKey(u.uid);
                                  }
                                  await s.save();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Signed in with Google'),
                                    ),
                                  );
                                  await Future.delayed(
                                    const Duration(milliseconds: 500),
                                  );
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ScannerScreen(
                                        cameras: widget.cameras,
                                        fdaChecker: widget.fdaChecker,
                                      ),
                                    ),
                                    (route) => false,
                                  );
                                },
                          icon: const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 28,
                          ),
                          label: const Text('Sign up with Google'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to sign in'),
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
