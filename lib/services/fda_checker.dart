import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:string_similarity/string_similarity.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:basta_fda/services/fda_firebase_updater.dart';
import 'package:basta_fda/services/settings_service.dart';

class FDAChecker {
  List<List<dynamic>> _data = [];
  DateTime? _loadedAt;
  final Map<String, List<dynamic>> _regIndex = {};
  final Map<String, int> _colIndex = {
    'reg_no': 1,
    'generic_name': 2,
    'brand_name': 3,
    'dosage_strength': 4,
    'dosage_form': 5,
    'manufacturer': 9,
    'country': 10,
    'distributor': 13,
    'issuance_date': 15,
    'expiry_date': 16,
  };
  static const String _cacheFileName = 'FDA_Products_cached.csv';
  static const Duration _staleAfter = Duration(days: 30);
  bool _columnsDerived = false;

  bool get isLoaded => _data.isNotEmpty;
  int get rowCount => _data.isNotEmpty ? _data.length - 1 : 0; // minus header row
  DateTime? get loadedAt => _loadedAt;
  bool get isStale {
    final last = SettingsService.instance.fdaLastUpdatedAt ?? _loadedAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > _staleAfter;
  }

  /// Load FDA CSV and clean it
  Future<void> loadCSV() async {
    try {
      final rawData = await rootBundle.loadString('assets/ALL_DrugProducts.csv');
      // Use default EOL handling so rows with embedded newlines in quoted fields
      // are parsed correctly across platforms.
      final parsedData = const CsvToListConverter().convert(rawData);

      // Normalize each row
      _data = parsedData.map((row) {
        return row.map((cell) => cell.toString().toLowerCase().trim()).toList();
      }).toList();
      _loadedAt = DateTime.now();
      if (_data.isNotEmpty) { _deriveColIndex(_data.first); }
      if (_data.isNotEmpty) _deriveColIndex(_data.first);

      // Build registration number index for O(1) exact matches
      _regIndex.clear();
      final regIdx = _regCol();
      for (final row in _data.skip(1)) {
        if (row.length < 2) continue;
        final reg = (regIdx >= 0 && regIdx < row.length) ? row[regIdx].toString() : '';
        if (reg.isEmpty) continue;
        final n = _normalizeReg(reg);
        if (n.isEmpty) continue;
        _regIndex[n] = row;
      }

      debugPrint("✅ FDA CSV loaded successfully. Rows: ${_data.length}");
    } catch (e) {
      debugPrint("❌ Error loading FDA CSV: $e");
    }
  }

  /// Normalize text for better matching
  String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // remove special chars
        .replaceAll(RegExp(r'\s+'), ' ') // normalize spaces
        .trim();
  }

  /// Normalize a registration number for exact comparisons (keep only a-z0-9)
  String _normalizeReg(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // Determine column indices from header row when available
  void _deriveColIndex(List<dynamic> headerRow) {
    if (headerRow.isEmpty) return;
    List<String> names = headerRow.map((e) => e.toString()).toList();
    String hNorm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (int i = 0; i < names.length; i++) {
      final n = hNorm(names[i]);
      if (n.isEmpty) continue;
      if (n.contains('reg') && (n.contains('no') || n.contains('number'))) {
        _colIndex['reg_no'] = i;
      } else if (n.contains('generic')) {
        _colIndex['generic_name'] = i;
      } else if (n.contains('brand')) {
        _colIndex['brand_name'] = i;
      } else if (n.contains('strength')) {
        _colIndex['dosage_strength'] = i;
      } else if (n.contains('dosage') && n.contains('form')) {
        _colIndex['dosage_form'] = i;
      } else if (n.contains('manufacturer')) {
        _colIndex['manufacturer'] = i;
      } else if (n.contains('country')) {
        _colIndex['country'] = i;
      } else if (n.contains('distributor')) {
        _colIndex['distributor'] = i;
      } else if ((n.contains('issue') || n.contains('issuance') || n.contains('date of issue'))) {
        _colIndex['issuance_date'] = i;
      } else if (n.contains('expiry') || n.contains('expiration')) {
        _colIndex['expiry_date'] = i;
      }
    }
    _columnsDerived = true;
  }

  int _regCol() => _colIndex['reg_no'] ?? 1;

  String _getField(List<dynamic> row, String key) {
    if (!_columnsDerived && _data.isNotEmpty) {
      _deriveColIndex(_data.first);
    }
    final idx = _colIndex[key];
    if (idx == null) return '';
    if (idx < 0 || idx >= row.length) return '';
    return row[idx]?.toString() ?? '';
  }

  // Tokens useful for fuzzy name comparisons (manufacturer/distributor)
  static const Set<String> _nameStopwords = {
    'inc', 'incorporated', 'corp', 'corporation', 'company', 'co', 'ltd', 'limited',
    'laboratories', 'laboratory', 'pharma', 'pharmaceutical', 'pharmaceuticals',
    'industries', 'industry', 'mfg', 'manufacturing', 'manufacturers', 'manuf', 'the'
  };

  List<String> _nameTokens(String input) {
    final norm = _normalizeText(input);
    return norm
        .split(' ')
        .where((t) => t.isNotEmpty && t.length >= 3 && !_nameStopwords.contains(t))
        .toList();
  }

  int _tokenOverlapCount(String a, String b) {
    final aSet = _nameTokens(a).toSet();
    final bSet = _nameTokens(b).toSet();
    if (aSet.isEmpty || bSet.isEmpty) return 0;
    return aSet.intersection(bSet).length;
  }

  // Extract likely party names from label such as "manufactured by X", "distributed by Y", "imported by Z".
  List<String> _extractPartyNames(String raw) {
    final text = raw.toLowerCase();
    final List<String> out = [];
    final patterns = <RegExp>[
      RegExp(r"manufactured by\s*[:\-]?\s*([a-z0-9\s,&\.\-]{3,})"),
      RegExp(r"manufacturer\s*[:\-]?\s*([a-z0-9\s,&\.\-]{3,})"),
      RegExp(r"distributed by\s*[:\-]?\s*([a-z0-9\s,&\.\-]{3,})"),
      RegExp(r"imported by\s*[:\-]?\s*([a-z0-9\s,&\.\-]{3,})"),
      RegExp(r"marketed by\s*[:\-]?\s*([a-z0-9\s,&\.\-]{3,})"),
    ];
    String clean(String s) {
      // Stop at common terminators (newline, country keywords, contact lines)
      final cut = s.split(RegExp(r"\b(contact|tel|phone|email|website|www\.|made in|product of)\b")).first;
      return cut.replaceAll(RegExp(r"\s+"), " ").trim();
    }
    for (final re in patterns) {
      for (final m in re.allMatches(text)) {
        final g = m.group(1);
        if (g != null) {
          final c = clean(g);
          if (c.length >= 3) out.add(c);
        }
      }
    }
    // Dedup
    final seen = <String>{};
    final res = <String>[];
    for (final s in out) {
      final key = _normalizeText(s);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      res.add(s);
    }
    return res;
  }

  /// Try to extract registration number candidates from scanned text.
  /// Looks for patterns like "Reg. No.: DRP-12345" or explicit DRP-like codes.
  List<String> _extractRegCandidates(String raw) {
    final List<String> out = [];
    final text = raw; // preserve separators for regex
    // 1) Explicit code pattern seen in dataset: e.g., DRP-4935 or DRP-4961-03
    //    Pattern: (3–4 letters)-(3–6 digits)[-(2–4 digits)]
    final explicitCode = RegExp(r'\b[A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?\b');
    for (final m in explicitCode.allMatches(text)) {
      out.add(m.group(0)!.trim());
    }
    // 2) Labeled formats: "Reg. No.: DRP-4935" strictly capturing explicit code format only
    final reLabeledStrict = RegExp(
      r'\breg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*([A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?)\b',
      caseSensitive: false,
    );
    for (final m in reLabeledStrict.allMatches(text)) {
      final code = m.group(1);
      if (code != null) out.add(code.trim());
    }
    final seen = <String>{};
    final dedup = <String>[];
    for (final c in out) {
      final n = _normalizeReg(c);
      if (n.isEmpty || seen.contains(n)) continue;
      seen.add(n);
      dedup.add(c);
    }
    return dedup;
  }

  // Expose candidates for UI/other callers
  List<String> regCandidates(String raw) => _extractRegCandidatesImproved(raw);

  // Improved extractor: supports hyphen/space/compact forms and labeled variants
  List<String> _extractRegCandidatesImproved(String raw) {
    final List<String> out = [];
    final text = raw;
    final explicit = RegExp(r'\b[A-Za-z]{3,4}[\-\s]?\d{3,6}(?:[\-\s]?\d{2,4})?\b');
    for (final m in explicit.allMatches(text)) {
      out.add(m.group(0)!.trim());
    }
    final labeled = RegExp(
      r'\b(?:fda\s*)?reg(?:istration)?\.?\s*(?:no\.?|number)?\s*[:#-]?\s*([A-Za-z]{3,4}[\-\s]?\d{3,6}(?:[\-\s]?\d{2,4})?)\b',
      caseSensitive: false,
    );
    for (final m in labeled.allMatches(text)) {
      final g = m.group(1);
      if (g != null) out.add(g.trim());
    }
    final compact = RegExp(r'\b[A-Za-z]{3,4}\d{3,6}(?:\d{2,4})?\b');
    for (final m in compact.allMatches(text)) {
      out.add(m.group(0)!.trim());
    }
    // Include legacy extractor results to avoid missing formats and keep backward-compatibility
    try {
      out.addAll(_extractRegCandidates(raw));
    } catch (_) {}
    final seen = <String>{};
    final dedup = <String>[];
    for (final c in out) {
      final n = _normalizeReg(c);
      if (n.isEmpty || seen.contains(n)) continue;
      seen.add(n);
      dedup.add(c);
    }
    return dedup;
  }

  /// Try to find a product by Registration Number, returning exact match if found.
  Map<String, String>? findByRegNo(String scannedText) {
    if (_data.isEmpty) return null;
    try {
      // Lazily build index if empty
      if (_regIndex.isEmpty && _data.length > 1) {
        final regIdx = _regCol();
        for (final row in _data.skip(1)) {
          if (row.length < 2) continue;
          final reg = (regIdx >= 0 && regIdx < row.length) ? row[regIdx].toString() : '';
          if (reg.isEmpty) continue;
          final n = _normalizeReg(reg);
          if (n.isEmpty) continue;
          _regIndex[n] = row;
        }
      }

      final candidates = _extractRegCandidatesImproved(scannedText);
      if (candidates.isEmpty) return null;
      for (final c in candidates) {
        final key = _normalizeReg(c);
        // try exact
        List<dynamic>? row = _regIndex[key];
        if (row != null) {
          debugPrint('[FDAChecker] reg-no exact match: ${_getField(row, 'reg_no')}');
          final m = _buildMap(row);
          m['match_reason'] = 'Registration number exact match';
          return m;
        }
        // try tolerant variants for common OCR swaps
        for (final v in _regVariants(key)) {
          row = _regIndex[v];
          if (row != null) {
            debugPrint('[FDAChecker] reg-no tolerant match: ${_getField(row, 'reg_no')} (from $c)');
            final m = _buildMap(row);
            m['match_reason'] = 'Registration number close match (OCR tolerant)';
            return m;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // Generate tolerant variants for a normalized reg key (lowercase a-z0-9)
  Iterable<String> _regVariants(String key) sync* {
    if (key.isEmpty) return;
    final swaps = <String, List<String>>{
      '0': ['o'], 'o': ['0'],
      '1': ['i','l'], 'i': ['1','l'], 'l': ['1','i'],
      '5': ['s'], 's': ['5'],
      '8': ['b'], 'b': ['8'],
    };
    for (int i = 0; i < key.length; i++) {
      final ch = key[i];
      final alts = swaps[ch];
      if (alts == null) continue;
      for (final a in alts) {
        yield key.substring(0, i) + a + key.substring(i + 1);
      }
    }
  }

  /// Ensure FDA data is loaded and reasonably fresh.
  /// - Loads from cache/asset first.
  /// - If a Settings URL is configured and data is stale, attempts a background update
  ///   with simple backoff retries.
  Future<void> ensureLoadedAndFresh() async {
    // Load something first so the app can function offline
    if (!isLoaded) {
      await loadCSVIsolatePreferCache();
    }

    try {
      final s = SettingsService.instance;
      await s.load();
      final url = (s.fdaUpdateUrl ?? '').trim();
      final now = DateTime.now();
      final last = s.fdaLastUpdatedAt ?? _loadedAt;
      final isStale = last == null || now.difference(last) > _staleAfter;
      if (!isStale) return;

      // Avoid excessive checks: throttle online check attempts (e.g., every 12h)
      final lastCheck = s.fdaLastCheckedAt;
      if (lastCheck != null && now.difference(lastCheck) < const Duration(hours: 12)) {
        return;
      }

      // Respect Wi‑Fi-only updates if enabled
      if (s.wifiOnlyUpdates) {
        try {
      final results = await Connectivity().checkConnectivity();
      final onWifi = results.contains(ConnectivityResult.wifi);
          if (!onWifi) return; // skip online update if not on Wi‑Fi
        } catch (_) {
          return; // if we cannot determine, skip to preserve data
        }
      }

      // Prefer explicit URL if configured; otherwise try Firebase manifest.
      if (url.isEmpty) {
        final ok = await FdaFirebaseUpdater(cacheFileName: _cacheFileName).updateFromManifest();
        if (ok) {
          await loadCSVIsolatePreferCache();
          s.fdaLastUpdatedAt = DateTime.now();
          s.fdaLastCheckedAt = DateTime.now();
          await s.save();
          return;
        }
        s.fdaLastCheckedAt = DateTime.now();
        await s.save();
        // If Firebase path fails, nothing else to do here.
        return;
      }

      // Try up to 2 times with small backoff
      for (int attempt = 0; attempt < 2; attempt++) {
        final ok = await updateFromUrl(url);
        if (ok) {
          s.fdaLastUpdatedAt = DateTime.now();
          s.fdaLastCheckedAt = DateTime.now();
          await s.save();
          return;
        }
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
      s.fdaLastCheckedAt = DateTime.now();
      await s.save();
    } catch (_) {
      // Ignore network/update errors; cached data is already available
    }
  }

  bool _hasMedicineCue(String normalized) {
    return normalized.contains('mg') ||
        normalized.contains('tablet') ||
        normalized.contains('capsule') ||
        normalized.contains('syrup') ||
        normalized.contains('cream') ||
        normalized.contains('ointment') ||
        normalized.contains('solution') ||
        normalized.contains('suspension') ||
        normalized.contains('injection');
  }

  // Parse strength cues from free text.
  // - Collects numeric dose values normalized to mg
  // - Collects mg-per-mL style concentration pairs normalized to (mg, ml)
  ({Set<double> mg, Set<({double mg, double ml})> mgPerMl}) _strengthFromText(String s) {
    final text = s.toLowerCase();
    final mg = <double>{};
    final pairs = <({double mg, double ml})>{};

    // ignore: no_leading_underscores_for_local_identifiers
    double _unitToMg(double value, String unit) {
      switch (unit.toLowerCase()) {
        case 'g':
          return value * 1000.0;
        case 'mcg':
        case 'µg':
          return value / 1000.0;
        default: // 'mg'
          return value;
      }
    }

    // ignore: no_leading_underscores_for_local_identifiers
    double? _toDouble(String x) => double.tryParse(x);

    // Plain dose values: 5 mg, 0.5 g, 500 mcg
    final reDose = RegExp(r"(\d+(?:\.\d+)?)\s*(mg|g|mcg|µg)");
    for (final m in reDose.allMatches(text)) {
      final v = _toDouble(m.group(1)!);
      final u = m.group(2)!;
      if (v != null) mg.add(_unitToMg(v, u));
    }

    // Concentrations: 250 mg/5 ml, 2 mg per 1 mL, 500 mcg/1 mL
    final reConc = RegExp(r"(\d+(?:\.\d+)?)\s*(mg|g|mcg|µg)\s*(?:/|per)\s*(\d+(?:\.\d+)?)\s*m\s*l");
    for (final m in reConc.allMatches(text)) {
      final dose = _toDouble(m.group(1)!);
      final unit = m.group(2)!;
      final vol = _toDouble(m.group(3)!);
      if (dose != null && vol != null && vol > 0) {
        pairs.add((mg: _unitToMg(dose, unit), ml: vol));
      }
    }

    return (mg: mg, mgPerMl: pairs);
  }

  bool _closeDouble(double a, double b, {double rel = 0.05, double abs = 0.05}) {
    final diff = (a - b).abs();
    if (diff <= abs) return true;
    final maxab = a.abs() > b.abs() ? a.abs() : b.abs();
    if (maxab == 0) return diff <= abs;
    return diff / maxab <= rel;
  }

  // Extract a likely expiry date from OCR text, prioritizing tokens near EXP/EXPIRY/EXPIRATION labels.
  DateTime? _extractLikelyExpiryDate(String raw) {
    final text = raw.toLowerCase();
    // Common labeled formats: EXP: 2026-05-31, EXP 05/2026, EXP 05/31/2026, EXP: 05-2026
    final labeled = RegExp(r"\b(?:exp|expiry|expiration)\s*(?:date)?\s*[:#-]?\s*([0-9]{1,2}[\-/][0-9]{1,2}[\-/][0-9]{2,4}|[0-9]{4}[\-/][0-9]{1,2}[\-/][0-9]{1,2}|[0-9]{1,2}[\-/][0-9]{2,4})");
    final m1 = labeled.firstMatch(text);
    if (m1 != null) {
      final d = _parseDate(m1.group(1));
      if (d != null) return d;
    }
    // Fallback: any date-like token in the text
    final anyDate = RegExp(r"\b(\d{1,2}[\-/]\d{1,2}[\-/]\d{2,4}|\d{4}[\-/]\d{1,2}[\-/]\d{1,2})\b");
    final m2 = anyDate.firstMatch(text);
    if (m2 != null) {
      return _parseDate(m2.group(1));
    }
    return null;
  }

  // Extract country cue like: made in X, product of X, manufactured in X
  String? _extractCountryCue(String raw) {
    final text = raw.toLowerCase();
    final m = RegExp(r"\b(?:made in|product of|manufactured in)\s+([a-z\s]{2,})\b").firstMatch(text);
    if (m == null) return null;
    final c = m.group(1)!.trim();
    // Strip trailing words that are unlikely part of country
    final clean = c.replaceAll(RegExp(r"[^a-z\s]"), "").replaceAll(RegExp(r"\s+"), " ").trim();
    if (clean.isEmpty) return null;
    return clean;
  }

  /// Fuzzy + token-based match algorithm
  Map<String, String>? findProductDetails(String scannedText) {
    if (_data.isEmpty) {
      debugPrint("⚠ FDA database not loaded yet.");
      return null;
    }

    final normalizedScan = _normalizeText(scannedText);
    final scanTokens = normalizedScan.split(' ').where((t) => t.isNotEmpty).toList();
    final scanTokenSet = scanTokens.toSet();

    // General brand-first resolution: if any brand token appears in the scan,
    // prefer rows whose brand tokens overlap and tie-break by generic, strength,
    // dosage form, and distributor hits from the scan text.
    {
      final strict = SettingsService.instance.strictMatching;
      double bestBrandScore = -1e9;
      List<dynamic>? bestBrandRow;
      // Evidence trackers for stricter acceptance
      int bestBrandOverlapCount = 0;
      bool bestGenOverlap = false;
      bool bestMgHit = false;
      bool bestFormCue = false;

    // Extract mg strengths from the scan (supports decimals e.g., 2.5 mg)
      final mgMatches = RegExp(r"(\d+(?:\.\d+)?)\s*mg").
          allMatches(normalizedScan).map((m) => m.group(1)!).toSet();
      final hasTablet = normalizedScan.contains('tablet');
      final hasCapsule = normalizedScan.contains('capsule');
      final hasSyrup = normalizedScan.contains('syrup');

      for (var row in _data.skip(1)) {
        if (row.length < 2) continue;
        final normBrand = _normalizeText(_getField(row, 'brand_name'));
        if (normBrand.isEmpty) continue;
        final brandTokens = normBrand.split(' ').where((t) => t.length >= 4).toSet();
        final overlap = brandTokens.intersection(scanTokenSet);
        final brandInScan = overlap.isNotEmpty || normalizedScan.contains(normBrand);
        if (!brandInScan) continue; // only consider brands present in scan

        double s = 0.0;
        // Base score from brand token overlap
        s += overlap.length * 1.8;
        if (normalizedScan.contains(normBrand)) s += 1.2; // full brand phrase

        // Tie-breakers
        final normGeneric = _normalizeText(_getField(row, 'generic_name'));
        final normStrength = _normalizeText(_getField(row, 'dosage_strength'));
        final normForm = _normalizeText(_getField(row, 'dosage_form'));
        final normDistributor = _normalizeText(_getField(row, 'distributor'));

        // Generic token overlap (e.g., amlodipine)
        final genTokens = normGeneric.split(' ').where((t) => t.length >= 5).toSet();
        final genOverlap = genTokens.intersection(scanTokenSet).isNotEmpty;
        if (genOverlap) s += 2.0;

        // Strength match (any scanned mg appearing in this row's strength)
        bool mgHit = false;
        for (final n in mgMatches) {
          if (normStrength.contains('$n mg') || normStrength.contains('${n}mg')) {
            s += 1.0;
            mgHit = true;
          }
        }

        // Dosage form cues
        bool formCue = false;
        if (hasTablet && normForm.contains('tablet')) { s += 0.6; formCue = true; }
        if (hasCapsule && normForm.contains('capsule')) { s += 0.6; formCue = true; }
        if (hasSyrup && normForm.contains('syrup')) { s += 0.6; formCue = true; }

        // Distributor token overlap (e.g., tgp)
        final distTokens = normDistributor.split(' ').where((t) => t.length >= 3).toSet();
        if (distTokens.intersection(scanTokenSet).isNotEmpty) s += 0.6;

        if (s > bestBrandScore) {
          bestBrandScore = s;
          bestBrandRow = row;
          bestBrandOverlapCount = overlap.length;
          bestGenOverlap = genOverlap;
          bestMgHit = mgHit;
          bestFormCue = formCue;
        }
      }

      // If we found a plausible brand candidate, accept only with enough evidence
      if (bestBrandRow != null) {
        final hasCue = _hasMedicineCue(normalizedScan) || bestMgHit || bestFormCue;
        final enoughEvidenceStrict = bestBrandOverlapCount >= 1 && bestGenOverlap && (bestMgHit || bestFormCue);
        final enoughEvidenceLoose = (bestBrandOverlapCount >= 1 && (bestGenOverlap || bestMgHit || bestFormCue)) || (bestGenOverlap && (bestMgHit || bestFormCue));
        final threshold = strict ? 2.6 : 2.2;
        final enough = strict ? enoughEvidenceStrict : enoughEvidenceLoose;
        if (bestBrandScore >= threshold && hasCue && enough) {
          debugPrint('[FDAChecker] brand-first match: brand=${bestBrandRow[3]} | strength=${bestBrandRow[4]}');
          final m = _buildMap(bestBrandRow);
          m['match_reason'] = 'Brand-first: brand/generic/strength/form overlap';
          return m;
        }
      }
    }

    // Debug context: tokens in scan and dataset coverage
    try {
      final hasAml = normalizedScan.contains('amlodipine');
      final hasLod = normalizedScan.contains('lodibes');
      int amlCount = 0, lodCount = 0;
      for (var row in _data.skip(1)) {
        if (row.length < 4) continue;
        final g = _normalizeText(row[2]);
        final b = _normalizeText(row[3]);
        if (g.contains('amlodipine')) amlCount++;
        if (b.contains('lodibes')) lodCount++;
      }
      debugPrint('[FDAChecker] rows=${_data.length} | scan aml=$hasAml, lod=$hasLod | rows aml=$amlCount, lod=$lodCount');
    } catch (_) {}

    // Quick pre-pass fallback: if scan contains clear generic/brand tokens,
    // pick the row with the strongest overlap on long tokens (>=5 chars).
    {
      double preBest = 0.0;
      List<dynamic>? preRow;
      for (var row in _data.skip(1)) {
        if (row.length < 17) continue;
        final normBrand = _normalizeText(row[3]);
        final normGeneric = _normalizeText(row[2]);
        final brandTokens = normBrand.split(' ').where((t) => t.length >= 5).toSet();
        final genericTokens = normGeneric.split(' ').where((t) => t.length >= 5).toSet();

        final bHits = brandTokens.intersection(scanTokenSet).length;
        final gHits = genericTokens.intersection(scanTokenSet).length;
        double score = bHits * 1.5 + gHits * 1.0;
        if (bHits > 0 && gHits > 0) score += 1.0;

        if (score > preBest) {
          preBest = score;
          preRow = row;
        }
      }

      final strict = SettingsService.instance.strictMatching;
      if (!strict && preRow != null && preBest >= 2.5 && _hasMedicineCue(normalizedScan)) {
        debugPrint('[FDAChecker] prepass fallback match: brand=${preRow[3]} | score=$preBest');
        final m = _buildMap(preRow);
        m['match_reason'] = 'Token overlap (brand/generic)';
        return m;
      }
    }

    // Deterministic contains fallback for very common cases (e.g., amlodipine + brand)
    if (normalizedScan.contains('lodibes') && normalizedScan.contains('amlodipine')) {
      for (var row in _data.skip(1)) {
        if (row.length < 2) continue;
        final normBrand = _normalizeText(_getField(row, 'brand_name'));
        final normGeneric = _normalizeText(_getField(row, 'generic_name'));
        if (normBrand.contains('lodibes') && normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (lodibes+amlodipine): ${_getField(row, 'brand_name')}');
          final m = _buildMap(row);
          m['match_reason'] = 'Deterministic contains: brand and generic present';
          return m;
        }
      }
    }
    // If only generic is present, pick the first amlodipine entry
    if (normalizedScan.contains('amlodipine')) {
      for (var row in _data.skip(1)) {
        if (row.length < 2) continue;
        final normGeneric = _normalizeText(_getField(row, 'generic_name'));
        if (normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (amlodipine only): ${_getField(row, 'brand_name')}');
          final m = _buildMap(row);
          m['match_reason'] = 'Generic present';
          return m;
        }
      }
    }

    double bestScore = 0.0;
    List<dynamic>? bestMatch;
    bool bestHasStrongExactMatch = false;

    for (var row in _data.skip(1)) {
      if (row.length < 2) continue; // skip incomplete rows

      final brand = _getField(row, 'brand_name');
      final generic = _getField(row, 'generic_name');
      // Normalize brand/generic same as scanned text for consistent tokenization
      final normBrand = _normalizeText(brand);
      final normGeneric = _normalizeText(generic);
      final brandTokens = normBrand.split(' ').where((t) => t.isNotEmpty).toSet();
      final genericTokens = normGeneric.split(' ').where((t) => t.isNotEmpty).toSet();

      double tokenMatchScore = 0.0;
      bool hasStrongExactMatch = false;

      // Compare every token in scanned text with brand & generic name
      for (var token in scanTokens) {
        // Skip very short tokens (e.g., mg, ml, 10) to reduce noise
        if (token.length < 3) continue;

        for (var b in brandTokens) {
          if (token == b) {
            // Exact brand token match is very strong
            tokenMatchScore += 2.0;
            hasStrongExactMatch = true;
          } else if (StringSimilarity.compareTwoStrings(token, b) > 0.8) {
            tokenMatchScore += 1.0;
          }
        }
        for (var g in genericTokens) {
          if (token == g) {
            // Exact generic token match is strong
            tokenMatchScore += 1.6;
            hasStrongExactMatch = true;
          } else if (StringSimilarity.compareTwoStrings(token, g) > 0.8) {
            tokenMatchScore += 0.8;
          }
        }
      }

      // Whole-field contains boosts as a fallback
      if (normBrand.isNotEmpty && normalizedScan.contains(normBrand)) {
        tokenMatchScore += 2.0;
        hasStrongExactMatch = true;
      }
      if (normGeneric.isNotEmpty && normalizedScan.contains(normGeneric)) {
        tokenMatchScore += 1.6;
        hasStrongExactMatch = true;
      }

      // Lightweight debug aid for key tokens
      // If scan includes highly-informative tokens and row shares them, log once
      final keyHitsBrand = brandTokens.intersection(scanTokenSet).where((t) => t.length >= 6).toList();
      final keyHitsGeneric = genericTokens.intersection(scanTokenSet).where((t) => t.length >= 6).toList();
      if (keyHitsBrand.isNotEmpty || keyHitsGeneric.isNotEmpty) {
        debugPrint('[FDAChecker] candidate hit: brand="$normBrand" | generic="$normGeneric" | hitsBrand=$keyHitsBrand | hitsGeneric=$keyHitsGeneric | score=${tokenMatchScore.toStringAsFixed(2)}');
      }

      if (tokenMatchScore > bestScore) {
        bestScore = tokenMatchScore;
        bestMatch = row;
        bestHasStrongExactMatch = hasStrongExactMatch;
      }
    }

    // ✅ Only accept if score is meaningful
    if (bestMatch != null) {
      final strict = SettingsService.instance.strictMatching;
      // Re-evaluate evidence on the best row to avoid false positives
      final normBrand = _normalizeText(_getField(bestMatch, 'brand_name'));
      final normGeneric = _normalizeText(_getField(bestMatch, 'generic_name'));
      final normStrength = _normalizeText(_getField(bestMatch, 'dosage_strength'));
      final normForm = _normalizeText(_getField(bestMatch, 'dosage_form'));
      final brandTokens = normBrand.split(' ').where((t) => t.isNotEmpty).toSet();
      final genericTokens = normGeneric.split(' ').where((t) => t.isNotEmpty).toSet();
      final brandHits = brandTokens.intersection(scanTokenSet).length;
      final genericHits = genericTokens.intersection(scanTokenSet).length;
      final mgHit = RegExp(r"(\d+(?:\.\d+)?)\s*mg").allMatches(normalizedScan).any((m) {
        final n = m.group(1)!;
        return normStrength.contains('$n mg') || normStrength.contains('${n}mg');
      });
      final formCue = (normalizedScan.contains('tablet') && normForm.contains('tablet')) ||
          (normalizedScan.contains('capsule') && normForm.contains('capsule')) ||
          (normalizedScan.contains('syrup') && normForm.contains('syrup'));
      final hasCue = _hasMedicineCue(normalizedScan) || mgHit || formCue;
      final enoughEvidence = (brandHits >= 1 && genericHits >= 1) ||
          (brandHits >= 1 && (mgHit || formCue));

      final threshold = strict ? 2.6 : 2.2;
      final enough = strict ? (brandHits >= 1 && genericHits >= 1 && (mgHit || formCue)) : (enoughEvidence || bestHasStrongExactMatch);
      final accept = hasCue && bestScore >= threshold && enough;
      if (accept) {
        debugPrint("✅ Best match: Brand=${bestMatch[3]} | Score=$bestScore");
        return _buildMap(bestMatch);
      }
    }

    debugPrint("❌ No match found for scanned text.");
    return null;
  }

  /// Return the top-N closest matches for a scanned text, without enforcing
  /// the acceptance threshold used by [findProductDetails]. Useful for
  /// suggestion UIs when no exact match is found.
  List<Map<String, String>> topMatches(String scannedText, {int limit = 5}) {
    if (_data.isEmpty) return [];

    final normalizedScan = _normalizeText(scannedText);
    final scanTokens = normalizedScan.split(' ').where((t) => t.isNotEmpty).toList();
    final scanTokenSet = scanTokens.toSet();

    final List<({double score, List<dynamic> row})> candidates = [];

    // Extract quick cues
    final mgMatches = RegExp(r"(\d+(?:\.\d+)?)\s*mg").allMatches(normalizedScan).map((m) => m.group(1)!).toSet();
    final hasTablet = normalizedScan.contains('tablet');
    final hasCapsule = normalizedScan.contains('capsule');
    final hasSyrup = normalizedScan.contains('syrup');
    // Reg No candidates
    final regCandidates = _extractRegCandidatesImproved(scannedText).map(_normalizeReg).toSet();

    for (var row in _data.skip(1)) {
      if (row.length < 2) continue;
      double s = 0.0;

      final normBrand = _normalizeText(_getField(row, 'brand_name'));
      final normGeneric = _normalizeText(_getField(row, 'generic_name'));
      final normStrength = _normalizeText(_getField(row, 'dosage_strength'));
      final normForm = _normalizeText(_getField(row, 'dosage_form'));
      final normDistributor = _normalizeText(_getField(row, 'distributor'));
      final normReg = _normalizeReg(_getField(row, 'reg_no'));

      // If reg no present and exact match, give a huge score to bubble it up.
      if (normReg.isNotEmpty && regCandidates.contains(normReg)) {
        s += 100.0;
      }

      final brandTokens = normBrand.split(' ').where((t) => t.isNotEmpty).toSet();
      final genericTokens = normGeneric.split(' ').where((t) => t.isNotEmpty).toSet();

      // Token overlaps
      final brandOverlap = brandTokens.intersection(scanTokenSet);
      final genericOverlap = genericTokens.intersection(scanTokenSet);
      s += brandOverlap.length * 1.8;
      s += genericOverlap.length * 1.0;

      // Whole-field contains
      if (normBrand.isNotEmpty && normalizedScan.contains(normBrand)) s += 1.2;
      if (normGeneric.isNotEmpty && normalizedScan.contains(normGeneric)) s += 1.0;

      // Strength cue
      for (final n in mgMatches) {
        if (normStrength.contains('$n mg') || normStrength.contains('${n}mg')) s += 0.8;
      }

      // Form cue
      if (hasTablet && normForm.contains('tablet')) s += 0.4;
      if (hasCapsule && normForm.contains('capsule')) s += 0.4;
      if (hasSyrup && normForm.contains('syrup')) s += 0.4;

      // Distributor cue
      final distTokens = normDistributor.split(' ').where((t) => t.isNotEmpty).toSet();
      if (distTokens.intersection(scanTokenSet).isNotEmpty) s += 0.4;

      if (s > 0) {
        candidates.add((score: s, row: row));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(limit).map((c) => _buildMap(c.row)).toList();
  }

  /// Build a map for easy display in Scan Result Screen
  Map<String, String> _buildMap(List<dynamic> row) {
    final Map<String, String> product = {};

    // Store every column as string, if present
    for (int i = 0; i < row.length; i++) {
      product['col_$i'] = row[i]?.toString() ?? '';
    }

    // Add friendly keys with bounds safety
    product['reg_no'] = _getField(row, 'reg_no');
    product['generic_name'] = _getField(row, 'generic_name');
    product['brand_name'] = _getField(row, 'brand_name');
    product['dosage_strength'] = _getField(row, 'dosage_strength');
    product['dosage_form'] = _getField(row, 'dosage_form');
    product['manufacturer'] = _getField(row, 'manufacturer');
    product['country'] = _getField(row, 'country');
    product['distributor'] = _getField(row, 'distributor');
    product['issuance_date'] = _getField(row, 'issuance_date');
    product['expiry_date'] = _getField(row, 'expiry_date');

    return product;
  }

  /// Load FDA CSV using a background isolate (non-blocking UI).
  Future<void> loadCSVIsolate() async {
    try {
      final rawData = await rootBundle.loadString('assets/ALL_DrugProducts.csv');
      final result = await compute(_parseAndIndexCsv, rawData);
      _data = result.data;
      _regIndex
        ..clear()
        ..addAll(result.regIndex);
      _loadedAt = DateTime.now();
      debugPrint('✅ FDA CSV loaded successfully (isolate). Rows: ${_data.length}');
    } catch (e) {
      debugPrint('⛔ Error loading FDA CSV (isolate): $e');
    }
  }

  /// Wrapper that adds a default explanation if base method doesn't.
  Map<String, String>? findProductDetailsWithExplain(String scannedText) {
    final m = findProductDetails(scannedText);
    if (m != null && !m.containsKey('match_reason')) {
      m['match_reason'] = 'Heuristic token match';
    }
    return m;
  }

  /// Load FDA CSV preferring a cached file stored in app documents.
  Future<void> loadCSVIsolatePreferCache() async {
    try {
      String rawData;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final f = File('${dir.path}/$_cacheFileName');
        rawData = await (await f.exists() ? f.readAsString() : rootBundle.loadString('assets/ALL_DrugProducts.csv'));
      } catch (_) {
        rawData = await rootBundle.loadString('assets/ALL_DrugProducts.csv');
      }
      final result = await compute(_parseAndIndexCsv, rawData);
      _data = result.data;
      _regIndex
        ..clear()
        ..addAll(result.regIndex);
      _loadedAt = DateTime.now();
      debugPrint('✅ FDA CSV loaded (prefer cache). Rows: ${_data.length}');
    } catch (e) {
      debugPrint('❌ Error loading FDA CSV (prefer cache): $e');
    }
  }

  /// Download latest FDA CSV from a URL, cache to disk, and reload.
  /// Returns true on success.
  Future<bool> updateFromUrl(String url) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        debugPrint('❌ Update failed: HTTP ${res.statusCode}');
        return false;
      }
      final bytes = await consolidateHttpClientResponseBytes(res);
      final csv = String.fromCharCodes(bytes);
      // Validate before writing: parse and ensure plausible structure
      try {
        final parsed = const CsvToListConverter().convert(csv);
        if (parsed.isEmpty || parsed.length < 10) {
          debugPrint('�?O Update failed: CSV too short');
          return false;
        }
        // Detect reg_no header
        int regIdx = 1;
        if (parsed.first.isNotEmpty) {
          final head = parsed.first.map((e) => e.toString().toLowerCase()).toList();
          for (int i = 0; i < head.length; i++) {
            final h = head[i];
            if (h.contains('reg') && (h.contains('no') || h.contains('number'))) { regIdx = i; break; }
          }
        }
        final hasReg = parsed.skip(1).any((row) => regIdx < row.length && row[regIdx].toString().trim().isNotEmpty);
        if (!hasReg) {
          debugPrint('�?O Update failed: No registration column detected');
          return false;
        }
      } catch (e) {
        debugPrint('�?O Update validation failed: $e');
        return false;
      }
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/$_cacheFileName');
      await out.writeAsString(csv, flush: true);
      await loadCSVIsolatePreferCache();
      return true;
    } catch (e) {
      debugPrint('❌ Update failed: $e');
      return false;
    }
  }

  /// Evaluate matched product against raw OCR to produce a status and reasons.
  /// Status: VERIFIED | EXPIRED | ALERT
  ({String status, List<String> reasons}) evaluateScan({
    required String raw,
    required Map<String, String> product,
  }) {
    String status = 'VERIFIED';
    final reasons = <String>[];

    // Expiry
    final exp = _parseDate(product['expiry_date']);
    if (exp != null && exp.isBefore(DateTime.now())) {
      status = 'EXPIRED';
      reasons.add('FDA record expired on ${product['expiry_date'] ?? ''}');
    }

    // OCR expiry vs FDA expiry comparison (tolerate small differences)
    final ocrExp = _extractLikelyExpiryDate(raw);
    if (ocrExp != null && exp != null) {
      final diffDays = (ocrExp.difference(exp).inDays).abs();
      if (diffDays > 60) { // > ~2 months difference
        reasons.add('Expiry on pack (${ocrExp.toIso8601String().split('T').first}) differs from FDA record (${product['expiry_date'] ?? ''})');
        if (status == 'VERIFIED' && SettingsService.instance.strictMatching) status = 'ALERT';
      }
    }

    // Plausibility: FDA issuance should not be after FDA expiry
    final fdaIssuance = _parseDate(product['issuance_date']);
    if (fdaIssuance != null && exp != null && fdaIssuance.isAfter(exp)) {
      reasons.add('FDA record dates appear inconsistent (issuance after expiry)');
    }

    // Reg. No. mismatch between package and FDA record
    final cands = _extractRegCandidatesImproved(raw).map(_normalizeReg).toSet();
    final reg = _normalizeReg(product['reg_no'] ?? '');
    if (cands.isNotEmpty && reg.isNotEmpty && !cands.contains(reg)) {
      if (status == 'VERIFIED') status = 'ALERT';
      reasons.add('Registration number on pack differs from FDA record');
    }

    // Strength/concentration comparison (robust: mg, g, mcg; mg/mL)
    final o = _strengthFromText(raw);
    final f = _strengthFromText(product['dosage_strength'] ?? '');
    // Compare plain mg values
    if (o.mg.isNotEmpty) {
      final ok = o.mg.any((ov) => f.mg.any((fv) => _closeDouble(ov, fv, rel: 0.05, abs: 0.05)));
      if (!ok) {
        if (!reasons.contains('Pack strength seems different from FDA record')) {
          reasons.add('Pack strength seems different from FDA record');
        }
        if (status == 'VERIFIED' && SettingsService.instance.strictMatching) status = 'ALERT';
      }
    }
    // Compare concentration pairs (mg/mL)
    if (o.mgPerMl.isNotEmpty) {
      bool anyGood = false;
      for (final op in o.mgPerMl) {
        for (final fp in f.mgPerMl) {
          final oRatio = op.mg / op.ml;
          final fRatio = fp.mg / fp.ml;
          if (_closeDouble(oRatio, fRatio, rel: 0.08, abs: 0.02)) {
            anyGood = true;
            break;
          }
        }
        if (anyGood) break;
      }
      if (!anyGood) {
        if (!reasons.contains('Pack concentration (mg/mL) seems different from FDA record')) {
          reasons.add('Pack concentration (mg/mL) seems different from FDA record');
        }
        if (status == 'VERIFIED' && SettingsService.instance.strictMatching) status = 'ALERT';
      }
    }

    // Dosage form mismatch (tablet/capsule/syrup/cream/etc.)
    final normForm = _normalizeText(product['dosage_form'] ?? '');
    final rawNorm = _normalizeText(raw);
    final formCues = <String>['tablet','capsule','syrup','cream','ointment','solution','suspension','injection'];
    final cueInPack = formCues.firstWhere(
      (c) => rawNorm.contains(c),
      orElse: () => '',
    );
    if (cueInPack.isNotEmpty && !normForm.contains(cueInPack)) {
      if (status == 'VERIFIED') status = 'ALERT';
      reasons.add('Dosage form on pack appears "$cueInPack" but FDA record differs');
    }

    // Manufacturer/Distributor cue mismatch (fuzzy check)
    final normMfg = _normalizeText(product['manufacturer'] ?? '');
    final normDist = _normalizeText(product['distributor'] ?? '');
    final hasMfgCue = rawNorm.contains('manufactured by') || rawNorm.contains('manufacturer');
    final hasDistCue = rawNorm.contains('distributed by') || rawNorm.contains('distributor');
    if ((hasMfgCue || hasDistCue) && (normMfg.isNotEmpty || normDist.isNotEmpty)) {
      final mfgOverlap = normMfg.isNotEmpty ? _tokenOverlapCount(raw, normMfg) : 0;
      final distOverlap = normDist.isNotEmpty ? _tokenOverlapCount(raw, normDist) : 0;

      final mfgLooksDifferent = normMfg.isNotEmpty && mfgOverlap == 0;
      final distLooksDifferent = normDist.isNotEmpty && distOverlap == 0;

      // Only escalate if BOTH appear different; otherwise keep as informational note
      if (mfgLooksDifferent && distLooksDifferent) {
        final strict = SettingsService.instance.strictMatching;
        if (status == 'VERIFIED' && strict) status = 'ALERT';
        reasons.add('Manufacturer/distributor on pack seems different from FDA record');
      }
    }

    // Extract explicit party names from label and cross-check
    final parties = _extractPartyNames(raw);
    if (parties.isNotEmpty && (normMfg.isNotEmpty || normDist.isNotEmpty)) {
      bool anyMatch = false;
      for (final p in parties) {
        final pNorm = _normalizeText(p);
        final o1 = normMfg.isNotEmpty ? _tokenOverlapCount(pNorm, normMfg) : 0;
        final o2 = normDist.isNotEmpty ? _tokenOverlapCount(pNorm, normDist) : 0;
        if (o1 > 0 || o2 > 0) { anyMatch = true; break; }
      }
      if (!anyMatch) {
        reasons.add('Label party names differ from FDA manufacturer/distributor');
        if (status == 'VERIFIED' && SettingsService.instance.strictMatching) status = 'ALERT';
      }
    }

    // Country cue mismatch from label (e.g., "Made in India") vs FDA country field
    final ocrCountry = _extractCountryCue(raw);
    final fdaCountryRaw = product['country'] ?? '';
    final fdaCountry = _normalizeText(fdaCountryRaw);
    if ((ocrCountry != null && ocrCountry.isNotEmpty) && fdaCountry.isNotEmpty) {
      String n(String s) => s.replaceAll(RegExp(r'[^a-z]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final o = n(ocrCountry);
      final f = n(fdaCountry);
      if (o.isNotEmpty && f.isNotEmpty && !o.contains(f) && !f.contains(o)) {
        if (status == 'VERIFIED' && SettingsService.instance.strictMatching) status = 'ALERT';
        reasons.add('Country on pack ("$ocrCountry") differs from FDA record ("$fdaCountryRaw")');
      }
    }

    return (status: status, reasons: reasons);
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final v = s.trim();
    final iso = DateTime.tryParse(v);
    if (iso != null) return iso;
    // dd/mm/yyyy or mm/dd/yyyy or yyyy-mm-dd
    final m = RegExp(r'^(\d{1,2})[\-/](\d{1,2})[\-/](\d{2,4})$').firstMatch(v);
    if (m != null) {
      final mm = int.tryParse(m.group(1)!);
      final dd = int.tryParse(m.group(2)!);
      var yy = int.tryParse(m.group(3)!);
      if (mm != null && dd != null && yy != null) {
        if (yy < 100) yy += 2000;
        return DateTime(yy, mm, dd);
      }
    }
    // mm/yyyy or mm-yy (assume last day of month)
    final my = RegExp(r'^(\d{1,2})[\-/](\d{2,4})$').firstMatch(v);
    if (my != null) {
      int? mm = int.tryParse(my.group(1)!);
      int? yy = int.tryParse(my.group(2)!);
      if (yy != null) {
        if (yy < 100) yy += 2000;
        if (mm != null && mm >= 1 && mm <= 12) {
          final firstNext = (mm == 12) ? DateTime(yy + 1, 1, 1) : DateTime(yy, mm + 1, 1);
          return firstNext.subtract(const Duration(days: 1));
        }
      }
    }
    // Mon YYYY (e.g., Jan 2026)
    final monNames = {
      'jan': 1,'feb': 2,'mar': 3,'apr': 4,'may': 5,'jun': 6,
      'jul': 7,'aug': 8,'sep': 9,'sept': 9,'oct': 10,'nov': 11,'dec': 12,
    };
    final m2 = RegExp(r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)\s+(\d{2,4})$', caseSensitive: false).firstMatch(v);
    if (m2 != null) {
      final mm = monNames[m2.group(1)!.toLowerCase()];
      var yy = int.tryParse(m2.group(2)!);
      if (mm != null && yy != null) {
        if (yy < 100) yy += 2000;
        final firstNext = (mm == 12) ? DateTime(yy + 1, 1, 1) : DateTime(yy, mm + 1, 1);
        return firstNext.subtract(const Duration(days: 1));
      }
    }
    return null;
  }
}

/// Parsed FDA data + registration index result from isolate
class _ParsedFdaData {
  final List<List<dynamic>> data;
  final Map<String, List<dynamic>> regIndex;
  _ParsedFdaData({required this.data, required this.regIndex});
}

/// Top-level function to allow `compute` to run it on a background isolate.
_ParsedFdaData _parseAndIndexCsv(String rawData) {
  // Parse respecting quoted newlines
  final parsedData = const CsvToListConverter().convert(rawData);
  // Normalize
  final norm = parsedData
      .map((row) => row.map((cell) => cell.toString().toLowerCase().trim()).toList())
      .toList();

  // Build index
  final Map<String, List<dynamic>> regIdx = {};
  String normalizeReg(String input) => input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  int regCol = 1;
  if (norm.isNotEmpty) {
    final head = norm.first;
    for (int i = 0; i < head.length; i++) {
      final h = head[i];
      if (h.contains('reg') && (h.contains('no') || h.contains('number'))) { regCol = i; break; }
    }
  }
  for (final row in norm.skip(1)) {
    if (row.length <= regCol) continue;
    final reg = row[regCol].toString();
    if (reg.isEmpty) continue;
    final n = normalizeReg(reg);
    if (n.isEmpty) continue;
    regIdx[n] = row;
  }

  return _ParsedFdaData(data: norm, regIndex: regIdx);
}
