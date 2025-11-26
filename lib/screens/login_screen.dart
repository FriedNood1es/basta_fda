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
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Sign In'),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.04),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 2,
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
                              const SizedBox(height: 10),
                              Text(
                                'Welcome back',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Match labels against FDA records. Packaging helper is optional.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _email,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon:
                                  const Icon(Icons.mail_outline_rounded),
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      final (ok, err) = await AuthService
                                          .instance
                                          .signInWithEmailPassword(
                                            _email.text.trim(),
                                            _password.text,
                                          );
                                      setState(() => _busy = false);
                                      if (!context.mounted) return;
                                      if (!ok) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                err ?? 'Login failed'),
                                          ),
                                        );
                                        return;
                                      }
                                      final s = SettingsService.instance;
                                      await s.load();
                                      s.isLoggedIn = true;
                                      s.guestMode = false;
                                      s.authProvider = 'email';
                                      final u =
                                          FirebaseAuth.instance.currentUser;
                                      if (u != null) {
                                        s.userEmail = u.email;
                                        s.displayName = u.displayName;
                                        await HistoryService.instance
                                            .switchProfileKey(u.uid);
                                      }
                                      await s.save();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Logged in successfully'),
                                        ),
                                      );
                                      await Future.delayed(
                                        const Duration(milliseconds: 500),
                                      );
                                      if (!context.mounted) return;
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
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      final (ok, err) = await AuthService
                                          .instance
                                          .signInWithGoogle();
                                      setState(() => _busy = false);
                                      if (!context.mounted) return;
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
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Signed in with Google'),
                                        ),
                                      );
                                      await Future.delayed(
                                        const Duration(milliseconds: 500),
                                      );
                                      if (!context.mounted) return;
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
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
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
                              const Text('•'),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final s = SettingsService.instance;
                                        await s.load();
                                        s.guestMode = true; // remember guest
                                        s.isLoggedIn = false;
                                        await s.save();
                                        await HistoryService.instance
                                            .switchProfileKey('guest');
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Continuing as guest',
                                            ),
                                          ),
                                        );
                                        await Future.delayed(
                                          const Duration(milliseconds: 450),
                                        );
                                        if (!context.mounted) return;
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
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 2,
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
                            const SizedBox(height: 10),
                            Text(
                              'Join bastaFDA',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create an account to sync history and reports.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            prefixIcon:
                                const Icon(Icons.person_outline_rounded),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _email,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon:
                                const Icon(Icons.mail_outline_rounded),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                            ),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          obscureText: !_showPassword,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    final (ok, err) =
                                        await AuthService.instance
                                            .registerWithEmailPassword(
                                      _email.text.trim(),
                                      _password.text,
                                      displayName: _name.text.trim(),
                                    );
                                    setState(() => _busy = false);
                                    if (!context.mounted) return;
                                    if (!ok) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                    final u =
                                        FirebaseAuth.instance.currentUser;
                                    if (u != null) {
                                      s.userEmail = u.email;
                                      s.displayName = u.displayName;
                                      await HistoryService.instance
                                          .switchProfileKey(u.uid);
                                    }
                                    await s.save();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text('Account created'),
                                      ),
                                    );
                                    await Future.delayed(
                                      const Duration(milliseconds: 600),
                                    );
                                    if (!context.mounted) return;
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
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() => _busy = true);
                                    final (ok, err) =
                                        await AuthService.instance
                                            .signInWithGoogle();
                                    setState(() => _busy = false);
                                    if (!context.mounted) return;
                                    if (!ok) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                                    final u =
                                        FirebaseAuth.instance.currentUser;
                                    if (u != null) {
                                      s.userEmail = u.email;
                                      s.displayName = u.displayName;
                                      await HistoryService.instance
                                          .switchProfileKey(u.uid);
                                    }
                                    await s.save();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text('Signed in with Google'),
                                      ),
                                    );
                                    await Future.delayed(
                                      const Duration(milliseconds: 500),
                                    );
                                    if (!context.mounted) return;
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
      ),
    );
  }
}
