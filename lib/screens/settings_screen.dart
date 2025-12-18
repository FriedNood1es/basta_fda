import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:basta_fda/services/auth_service.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:basta_fda/services/image_classifier.dart';
import 'package:basta_fda/data/packaging_trained_products.dart';

class SettingsScreen extends StatefulWidget {
  final FDAChecker fdaChecker;
  const SettingsScreen({super.key, required this.fdaChecker});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.load().then((_) async {
      if (mounted) setState(() => _loading = false);
    });
  }

  Widget _accountSummary() {
    final s = SettingsService.instance;
    String title;
    String subtitle;
    if (s.guestMode) {
      title = 'Guest mode';
      subtitle = 'Not signed in';
    } else if (Firebase.apps.isNotEmpty &&
        FirebaseAuth.instance.currentUser != null) {
      final u = FirebaseAuth.instance.currentUser!;
      title = (u.displayName?.isNotEmpty ?? false)
          ? u.displayName!
          : (u.email ?? 'Signed in');
      subtitle = (u.email ?? '').isNotEmpty
          ? (u.email!)
          : 'Google/Firebase account';
    } else if (s.isLoggedIn) {
      title = (s.displayName?.isNotEmpty ?? false)
          ? s.displayName!
          : (s.userEmail ?? 'Signed in');
      subtitle = (s.userEmail ?? '').isNotEmpty
          ? s.userEmail!
          : 'Account active';
    } else {
      title = 'Not signed in';
      subtitle = 'Tap Logout to return to Login';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            child: Text(
              (title.isNotEmpty ? title[0] : '?').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _accountSummary(),
                if (s.guestMode)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.person_outline_rounded,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Guest mode is active. Your session isn't signed in.",
                          ),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  title: const Text('Review before search'),
                  subtitle: const Text('Show the review sheet before matching'),
                  value: s.reviewBeforeSearch,
                  onChanged: (v) => setState(() {
                    s.reviewBeforeSearch = v;
                    s.save();
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('Refresh FDA database (cache/asset)'),
                  subtitle: Builder(
                    builder: (context) {
                      if (!widget.fdaChecker.isLoaded) {
                        return const Text('Not loaded yet');
                      }
                      final s = SettingsService.instance;
                      final last =
                          s.fdaLastUpdatedAt ?? widget.fdaChecker.loadedAt;
                      final stale = widget.fdaChecker.isStale;
                      final lastText = last != null
                          ? last.toString()
                          : 'unknown';
                      final staleText = stale ? ' (STALE)' : '';
                      return Text(
                        'Loaded rows: ${widget.fdaChecker.rowCount} - Last updated: $lastText$staleText',
                      );
                    },
                  ),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await widget.fdaChecker.loadCSVIsolatePreferCache();
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('FDA data reloaded')),
                    );
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Packaging coverage (trained list)'),
                  subtitle: const Text(
                    'See products with packaging helper support',
                  ),
                  onTap: () => _showPackagingCoverageSheet(context),
                ),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Packaging authenticity threshold'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adjust how strict the packaging helper is before marking results suspicious. Current: ${(s.packagingSuspicionThreshold * 100).toStringAsFixed(0)}%',
                      ),
                      Slider(
                        value: s.packagingSuspicionThreshold,
                        min: 0.4,
                        max: 0.7,
                        divisions: 6,
                        label:
                            '${(s.packagingSuspicionThreshold * 100).toStringAsFixed(0)}%',
                        onChanged: (value) {
                          setState(() {
                            s.packagingSuspicionThreshold = value;
                          });
                        },
                        onChangeEnd: (value) {
                          SettingsService.instance.packagingSuspicionThreshold =
                              value;
                          SettingsService.instance.save();
                          PackagingImageClassifier.instance
                              .updateConfidenceConfig(
                                suspiciousThreshold: value,
                              );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                AboutListTile(
                  applicationName: 'bastaFDA',
                  applicationVersion: '1.0.0',
                  applicationLegalese: 'Ac 2025',
                  applicationIcon: Image.asset('assets/logo.png', height: 40),
                  aboutBoxChildren: const [
                    SizedBox(height: 12),
                    Text(
                      'Your first defense against suspicious packaging.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'bastaFDA: Counterfeit Product Scanner helps you verify if medicines and supplements are FDA-approved in seconds. Just scan the packaging with your phone, and the app uses OCR to check product details against the FDA database. Get instant results - Registered, Not Found, or Flagged - and report suspicious products to stay safe and informed.',
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Disclaimer',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'We match label text to FDA registration records. Packaging authenticity still needs your judgment - please report anything that looks tampered.',
                    ),
                  ],
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                  ),
                  title: Text(s.guestMode ? 'End Guest Session' : 'Logout'),
                  subtitle: Text(
                    s.guestMode
                        ? 'Return to login screen'
                        : 'End session and return to login',
                  ),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(
                          s.guestMode ? 'End guest session?' : 'Logout?',
                        ),
                        content: Text(
                          s.guestMode
                              ? 'You will need to login or skip again next time.'
                              : 'You will need to login again next time.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(s.guestMode ? 'End' : 'Logout'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      final s = SettingsService.instance;
                      await s.load();
                      s.isLoggedIn = false;
                      s.guestMode = false;
                      s.userEmail = null;
                      s.displayName = null;
                      await s.save();
                      await AuthService.instance.signOut();
                      // Switch history to guest profile on logout
                      await HistoryService.instance.switchProfileKey('guest');
                      try {
                        final cameras = await availableCameras();
                        if (!context.mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => LoginScreen(
                              cameras: cameras,
                              fdaChecker: widget.fdaChecker,
                            ),
                          ),
                          (route) => false,
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      }
                    }
                  },
                ),
              ],
            ),
    );
  }
}

void _showPackagingCoverageSheet(BuildContext context) {
  final grouped = PackagingCoverage.byCategory();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Packaging coverage',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'These products have trained packaging references. The list only appears here to keep the scanner uncluttered.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: grouped.keys.length,
                  itemBuilder: (ctx, idx) {
                    final category = grouped.keys.elementAt(idx);
                    final items = grouped[category] ?? [];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category,
                            style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...items.map(
                            (p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(p.name)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
