import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:basta_fda/models/scan_verdict.dart';

class HistoryEntry {
  final DateTime timestamp;
  final String scannedText;
  final Map<String, String>? productInfo; // null when not found
  final String status; // e.g., RECOGNIZED / NOT FOUND / EXPIRED
  final Map<String, String>? imageInfo;
  final RegistrationStatus registrationStatus;
  final ImageCheckStatus imageStatus;
  final String? regNumber;

  HistoryEntry({
    required this.timestamp,
    required this.scannedText,
    required this.productInfo,
    required this.status,
    this.imageInfo,
    required this.registrationStatus,
    required this.imageStatus,
    this.regNumber,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'scannedText': scannedText,
        'productInfo': productInfo,
        'status': status,
        'imageInfo': imageInfo,
        'registrationStatus': registrationStatus.name,
        'imageStatus': imageStatus.name,
        'regNumber': regNumber,
      };

  static HistoryEntry fromJson(Map<String, dynamic> json) {
    RegistrationStatus parseReg(String? raw, Map<String, String>? product) {
      if (raw == null || raw.isEmpty) {
        return product != null
            ? RegistrationStatus.registered
            : RegistrationStatus.unregistered;
      }
      return RegistrationStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => product != null
            ? RegistrationStatus.registered
            : RegistrationStatus.unregistered,
      );
    }

    ImageCheckStatus parseImg(String? raw, Map<String, String>? imageInfo) {
      if (raw == null || raw.isEmpty) {
        return imageInfo != null
            ? ImageCheckStatus.recognized
            : ImageCheckStatus.skipped;
      }
      return ImageCheckStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => imageInfo != null
            ? ImageCheckStatus.recognized
            : ImageCheckStatus.skipped,
      );
    }

    final product =
        (json['productInfo'] as Map?)?.cast<String, String>();
    final imageInfo =
        (json['imageInfo'] as Map?)?.cast<String, String>();
    return HistoryEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      scannedText: (json['scannedText'] ?? '') as String,
      productInfo: product,
      status: (json['status'] ?? '') as String,
      imageInfo: imageInfo,
      registrationStatus: parseReg(
        json['registrationStatus'] as String?,
        product,
      ),
      imageStatus: parseImg(json['imageStatus'] as String?, imageInfo),
      regNumber: (() {
        final raw = json['regNumber'];
        if (raw is String) {
          final trimmed = raw.trim();
          if (trimmed.isNotEmpty) return trimmed;
        }
        return null;
      })(),
    );
  }
}

class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  final List<HistoryEntry> _entries = [];
  bool _loaded = false;
  String _profileKey = 'guest';

  String get currentProfile => _profileKey;

  // Sanitize profile key for filename safety (letters, numbers, _ and -)
  String _safe(String key) {
    final lower = key.toLowerCase();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final squashed = replaced.replaceAll(RegExp(r'_+'), '_');
    return squashed.trim();
  }

  List<HistoryEntry> get entries => List.unmodifiable(_entries.reversed);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final key = _safe(_profileKey).isEmpty ? 'guest' : _safe(_profileKey);
    return File('${dir.path}/history_$key.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
      // Simple migration: if switching to guest and legacy file exists, import it
      if (!(await f.exists()) && _profileKey == 'guest') {
        final dir = await getApplicationDocumentsDirectory();
        final legacy = File('${dir.path}/history.json');
        if (await legacy.exists()) {
          try {
            final legacyRaw = await legacy.readAsString();
            final list = (jsonDecode(legacyRaw) as List)
                .cast<Map>()
                .map((m) => HistoryEntry.fromJson(m.cast<String, dynamic>()))
                .toList();
            _entries
              ..clear()
              ..addAll(list);
            await _persist(); // save into new per-profile file
            _loaded = true;
            return;
          } catch (_) {
            // ignore corrupt legacy file
          }
        }
      }
      if (await f.exists()) {
        final raw = await f.readAsString();
        final list = (jsonDecode(raw) as List).cast<Map>().map((m) => HistoryEntry.fromJson(m.cast<String, dynamic>())).toList();
        _entries
          ..clear()
          ..addAll(list);
      }
    } catch (_) {
      // ignore corrupt file
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await f.writeAsString(data, flush: true);
    } catch (_) {
      // ignore
    }
  }

  /// Switch the active history profile (e.g., 'guest' or a Firebase UID).
  /// This clears in-memory entries and loads the target profile file.
  Future<void> switchProfileKey(String key) async {
    final k = _safe(key.isEmpty ? 'guest' : key);
    if (k == _profileKey && _loaded) return;
    _profileKey = k.isEmpty ? 'guest' : k;
    _loaded = false;
    _entries.clear();
    await load();
  }

  Future<void> addEntry({
    required String scannedText,
    required Map<String, String>? productInfo,
    required String status,
    Map<String, String>? imageInfo,
    required RegistrationStatus registrationStatus,
    required ImageCheckStatus imageStatus,
    String? regNumber,
  }) async {
    await load();
    _entries.add(
      HistoryEntry(
        timestamp: DateTime.now(),
        scannedText: scannedText,
        productInfo: productInfo,
        status: status,
        imageInfo: imageInfo,
        registrationStatus: registrationStatus,
        imageStatus: imageStatus,
        regNumber: regNumber,
      ),
    );
    await _persist();
  }

  Future<void> clear() async {
    await load();
    _entries.clear();
    await _persist();
  }

  /// Export the current history as a JSON file in the app documents folder.
  /// Returns the saved file path on success, or null on failure.
  Future<String?> export() async {
    try {
      await load();
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final fname =
          'history_export_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.json';
      final out = File('${dir.path}/$fname');
      final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await out.writeAsString(data, flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }
}



