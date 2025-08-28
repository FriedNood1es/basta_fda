import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class HistoryEntry {
  final DateTime timestamp;
  final String scannedText;
  final Map<String, String>? productInfo; // null when not found
  final String status; // e.g., VERIFIED / NOT FOUND / EXPIRED

  HistoryEntry({
    required this.timestamp,
    required this.scannedText,
    required this.productInfo,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'scannedText': scannedText,
        'productInfo': productInfo,
        'status': status,
      };

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        scannedText: (json['scannedText'] ?? '') as String,
        productInfo: (json['productInfo'] as Map?)?.cast<String, String>(),
        status: (json['status'] ?? '') as String,
      );
}

class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  final List<HistoryEntry> _entries = [];
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries.reversed);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/history.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
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

  Future<void> addEntry({required String scannedText, required Map<String, String>? productInfo, required String status}) async {
    await load();
    _entries.add(HistoryEntry(timestamp: DateTime.now(), scannedText: scannedText, productInfo: productInfo, status: status));
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
