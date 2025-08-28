import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/login_screen.dart';

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
    SettingsService.instance.load().then((_) => setState(() => _loading = false));
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
                if (s.guestMode)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, color: Colors.orange),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Guest mode is active. Your session isn\'t signed in.')),
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
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('Refresh FDA database'),
                  subtitle: Text(
                    widget.fdaChecker.isLoaded
                        ? 'Loaded rows: ${widget.fdaChecker.rowCount}${widget.fdaChecker.loadedAt != null ? ' • ${widget.fdaChecker.loadedAt}' : ''}'
                        : 'Not loaded yet',
                  ),
                  onTap: () async {
                    await widget.fdaChecker.loadCSV();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FDA data reloaded')));
                      setState(() {});
                    }
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
                      await s.save();
                      try {
                        final cameras = await availableCameras();
                        if (!mounted) return;
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => LoginScreen(cameras: cameras, fdaChecker: widget.fdaChecker)),
                          (route) => false,
                        );
                      } catch (_) {
                        if (!mounted) return;
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
                ),
              ],
            ),
    );
  }
}
