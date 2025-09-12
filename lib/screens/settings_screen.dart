import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:basta_fda/services/auth_service.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/login_screen.dart';
import 'package:basta_fda/screens/reports_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:flutter/services.dart' show TextInputFormatter, FilteringTextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  final FDAChecker fdaChecker;
  const SettingsScreen({super.key, required this.fdaChecker});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.load().then((_) async {
      if (mounted) setState(() => _loading = false);
      // Determine admin (best-effort; safe if Firebase not configured)
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          final snap = await FirebaseFirestore.instance.collection('admins').doc(u.uid).get();
          if (mounted) setState(() => _isAdmin = snap.exists);
        }
      } catch (_) {
        if (mounted) setState(() => _isAdmin = false);
      }
    });
  }

  Widget _accountSummary() {
    final s = SettingsService.instance;
    String title;
    String subtitle;
    if (s.guestMode) {
      title = 'Guest mode';
      subtitle = 'Not signed in';
    } else if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      final u = FirebaseAuth.instance.currentUser!;
      title = (u.displayName?.isNotEmpty ?? false) ? u.displayName! : (u.email ?? 'Signed in');
      subtitle = (u.email ?? '').isNotEmpty ? (u.email!) : 'Google/Firebase account';
    } else if (s.isLoggedIn) {
      title = (s.displayName?.isNotEmpty ?? false) ? s.displayName! : (s.userEmail ?? 'Signed in');
      subtitle = (s.userEmail ?? '').isNotEmpty ? s.userEmail! : 'Account active';
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
            child: Text((title.isNotEmpty ? title[0] : '?').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Theme.of(context).hintColor)),
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
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.person_outline_rounded, color: Colors.orange),
                        SizedBox(width: 10),
                        Expanded(child: Text("Guest mode is active. Your session isn't signed in.")),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                SwitchListTile(
                  title: const Text('Enable live OCR by default'),
                  subtitle: const Text('Show live suggestions while aiming the camera'),
                  value: s.liveOcrDefault,
                  onChanged: (v) => setState(() {
                    s.liveOcrDefault = v;
                    s.save();
                  }),
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
                SwitchListTile(
                  title: const Text('Wi‑Fi only for data updates'),
                  subtitle: const Text('Use Wi‑Fi for downloading the latest FDA CSV'),
                  value: s.wifiOnlyUpdates,
                  onChanged: (v) => setState(() {
                    s.wifiOnlyUpdates = v;
                    s.save();
                  }),
                ),
                SwitchListTile(
                  title: const Text("Smart 'Add side' prompt"),
                  subtitle: const Text('Suggest adding another package side when OCR looks incomplete'),
                  value: s.smartAddSidePrompt,
                  onChanged: (v) => setState(() {
                    s.smartAddSidePrompt = v;
                    s.save();
                  }),
                ),
                SwitchListTile(
                  title: const Text('Strict matching'),
                  subtitle: const Text('Reduce false positives (brand + generic + cues)'),
                  value: s.strictMatching,
                  onChanged: (v) => setState(() {
                    s.strictMatching = v;
                    s.save();
                  }),
                ),
                SwitchListTile(
                  title: const Text('Update FDA data on Wi‑Fi only'),
                  subtitle: const Text('Skip online refresh when not connected to Wi‑Fi'),
                  value: s.wifiOnlyUpdates,
                  onChanged: (v) => setState(() {
                    s.wifiOnlyUpdates = v;
                    s.save();
                  }),
                ),
                if (_isAdmin) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cloud_download_rounded),
                  title: const Text('Update FDA database from URL'),
                  subtitle: Text(
                    (SettingsService.instance.fdaUpdateUrl?.isNotEmpty ?? false)
                        ? SettingsService.instance.fdaUpdateUrl!
                        : 'Download latest CSV and cache to device',
                  ),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final controller = TextEditingController(text: '');
                    final url = await showDialog<String?>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: const Text('Enter CSV URL'),
                        content: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(dialogCtx).viewInsets.bottom,
                          ),
                          child: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/ALL_DrugProducts.csv',
                            ),
                            autofocus: true,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Download')),
                        ],
                      ),
                    );
                    if (url == null || url.isEmpty) return;
                    messenger.showSnackBar(const SnackBar(content: Text('Downloading update…')));
                    final ok = await widget.fdaChecker.updateFromUrl(url);
                    if (!mounted) return;
                    if (ok) {
                      final svc = SettingsService.instance;
                      await svc.load();
                      svc.fdaUpdateUrl = url;
                      svc.fdaLastUpdatedAt = DateTime.now();
                      await svc.save();
                    }
                    messenger.showSnackBar(SnackBar(content: Text(ok ? 'FDA data updated' : 'Update failed')));
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                if ((SettingsService.instance.fdaUpdateUrl?.isNotEmpty ?? false))
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_rounded),
                    title: const Text('Check for updates now'),
                    subtitle: const Text('Uses the saved URL and updates if data is stale'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(const SnackBar(content: Text('Checking for updates…')));
                      await widget.fdaChecker.ensureLoadedAndFresh();
                      if (!mounted) return;
                      messenger.showSnackBar(const SnackBar(content: Text('Update check complete')));
                      setState(() {});
                    },
                  ),
                ],
                if (_isAdmin) ...[
                const Divider(),
                // Admin: FDA CSV update configuration
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FDA CSV Update', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: TextEditingController(text: s.fdaUpdateUrl ?? ''),
                        decoration: const InputDecoration(
                          labelText: 'CSV Update URL (https://…) ',
                          hintText: 'Public CSV URL; leave empty to use Firebase manifest',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.url,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r"\s")),
                        ],
                        onSubmitted: (v) async {
                          s.fdaUpdateUrl = v.trim().isEmpty ? null : v.trim();
                          await s.save();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update URL saved')));
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                messenger.showSnackBar(const SnackBar(content: Text('Checking for online update…')));
                                try {
                                  await widget.fdaChecker.ensureLoadedAndFresh();
                                  if (!mounted) return;
                                  messenger.showSnackBar(const SnackBar(content: Text('Check complete')));
                                  setState(() {});
                                } catch (_) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(const SnackBar(content: Text('Check failed')));
                                }
                              },
                              icon: const Icon(Icons.cloud_download_rounded),
                              label: const Text('Check online update now'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.verified_user_rounded),
                  title: const Text('Check admin status'),
                  subtitle: const Text('Shows current Firebase project, UID, and admin check'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      if (Firebase.apps.isEmpty) {
                        await Firebase.initializeApp();
                      }
                      final app = Firebase.app();
                      final projectId = app.options.projectId ?? '(unknown)';
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '(not signed in)';
                      final email = FirebaseAuth.instance.currentUser?.email ?? '';
                      bool isAdmin = false;
                      String? errorDetail;
                      String docPath = 'admins/$uid';
                      try {
                        if (uid != '(not signed in)') {
                          final snap = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
                          isAdmin = snap.exists;
                        }
                      } catch (e) {
                        errorDetail = e.toString();
                      }
                      if (!mounted) return;
                      await showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Admin status'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Project ID: $projectId'),
                              const SizedBox(height: 6),
                              Text('UID: $uid'),
                              const SizedBox(height: 6),
                              Text('Doc path: $docPath'),
                              if (email.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Email: $email'),
                              ],
                              const SizedBox(height: 12),
                              Text(isAdmin ? 'You ARE an admin.' : 'You are NOT an admin.',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: isAdmin ? Colors.green : Theme.of(context).colorScheme.error)),
                              if (errorDetail != null && errorDetail!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text('Error while reading admin doc:', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                const SizedBox(height: 4),
                                Text(errorDetail!, style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 6),
                                const Text('Tip: allow authenticated read on /admins/{uid} in Firestore rules.' , style: TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                          ],
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(const SnackBar(content: Text('Firebase not configured.')));
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.list_alt_rounded),
                  title: const Text('View submitted reports (admin)'),
                  subtitle: const Text('Requires Firebase configuration'),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                  },
                ),
                const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('Refresh FDA database (cache/asset)'),
                  subtitle: Builder(builder: (context) {
                    if (!widget.fdaChecker.isLoaded) return const Text('Not loaded yet');
                    final s = SettingsService.instance;
                    final last = s.fdaLastUpdatedAt ?? widget.fdaChecker.loadedAt;
                    final stale = widget.fdaChecker.isStale;
                    final lastText = last != null ? last.toString() : 'unknown';
                    final staleText = stale ? ' • STALE' : '';
                    return Text('Loaded rows: ${widget.fdaChecker.rowCount} • Last updated: $lastText$staleText');
                  }),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await widget.fdaChecker.loadCSVIsolatePreferCache();
                    if (!context.mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('FDA data reloaded')));
                    setState(() {});
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  title: Text(s.guestMode ? 'End Guest Session' : 'Logout'),
                  subtitle: Text(s.guestMode ? 'Return to login screen' : 'End session and return to login'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(s.guestMode ? 'End guest session?' : 'Logout?'),
                        content: Text(s.guestMode ? 'You will need to login or skip again next time.' : 'You will need to login again next time.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(s.guestMode ? 'End' : 'Logout')),
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
                          MaterialPageRoute(builder: (_) => LoginScreen(cameras: cameras, fdaChecker: widget.fdaChecker)),
                          (route) => false,
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      }
                    }
                  },
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
                      'Your first defense against fake medicines.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'bastaFDA: Counterfeit Product Scanner helps you verify if medicines and supplements are FDA-approved in seconds. Just scan the packaging with your phone, and the app uses OCR to check product details against the FDA database. Get instant results — Registered, Not Found, or Flagged — and report suspicious products to stay safe and informed.',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

