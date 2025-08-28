import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  bool _loaded = false;
  bool liveOcrDefault = false;
  bool reviewBeforeSearch = true;
  bool hasSeenWelcome = false;
  bool isLoggedIn = false;
  bool guestMode = false;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        liveOcrDefault = (json['liveOcrDefault'] ?? false) as bool;
        reviewBeforeSearch = (json['reviewBeforeSearch'] ?? true) as bool;
        hasSeenWelcome = (json['hasSeenWelcome'] ?? false) as bool;
        isLoggedIn = (json['isLoggedIn'] ?? false) as bool;
        guestMode = (json['guestMode'] ?? false) as bool;
      }
    } catch (_) {
      // defaults
    } finally {
      _loaded = true;
    }
  }

  Future<void> save() async {
    final f = await _file();
    final data = jsonEncode({
      'liveOcrDefault': liveOcrDefault,
      'reviewBeforeSearch': reviewBeforeSearch,
      'hasSeenWelcome': hasSeenWelcome,
      'isLoggedIn': isLoggedIn,
      'guestMode': guestMode,
    });
    await f.writeAsString(data, flush: true);
  }
}
