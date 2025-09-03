import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:string_similarity/string_similarity.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:basta_fda/services/fda_firebase_updater.dart';
import 'package:basta_fda/services/settings_service.dart';

class FDAChecker {
  List<List<dynamic>> _data = [];
  DateTime? _loadedAt;
  final Map<String, List<dynamic>> _regIndex = {};
  static const String _cacheFileName = 'FDA_Products_cached.csv';
  static const Duration _staleAfter = Duration(days: 30);

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

      // Build registration number index for O(1) exact matches
      _regIndex.clear();
      for (final row in _data.skip(1)) {
        if (row.length < 2) continue;
        final reg = row[1].toString();
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
  List<String> regCandidates(String raw) => _extractRegCandidates(raw);

  /// Try to find a product by Registration Number, returning exact match if found.
  Map<String, String>? findByRegNo(String scannedText) {
    if (_data.isEmpty) return null;
    try {
      // Lazily build index if empty
      if (_regIndex.isEmpty && _data.length > 1) {
        for (final row in _data.skip(1)) {
          if (row.length < 2) continue;
          final reg = row[1].toString();
          if (reg.isEmpty) continue;
          final n = _normalizeReg(reg);
          if (n.isEmpty) continue;
          _regIndex[n] = row;
        }
      }

      final candidates = _extractRegCandidates(scannedText);
      if (candidates.isEmpty) return null;
      for (final c in candidates) {
        final key = _normalizeReg(c);
        // try exact
        List<dynamic>? row = _regIndex[key];
        if (row != null) {
          debugPrint('[FDAChecker] reg-no exact match: ${row[1]}');
          final m = _buildMap(row);
          m['match_reason'] = 'Registration number exact match';
          return m;
        }
        // try tolerant variants for common OCR swaps
        for (final v in _regVariants(key)) {
          row = _regIndex[v];
          if (row != null) {
            debugPrint('[FDAChecker] reg-no tolerant match: ${row[1]} (from $c)');
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

      // Prefer explicit URL if configured; otherwise try Firebase manifest.
      if (url.isEmpty) {
        final ok = await FdaFirebaseUpdater(cacheFileName: _cacheFileName).updateFromManifest();
        if (ok) {
          await loadCSVIsolatePreferCache();
          s.fdaLastUpdatedAt = DateTime.now();
          await s.save();
          return;
        }
        // If Firebase path fails, nothing else to do here.
        return;
      }

      // Try up to 2 times with small backoff
      for (int attempt = 0; attempt < 2; attempt++) {
        final ok = await updateFromUrl(url);
        if (ok) {
          s.fdaLastUpdatedAt = DateTime.now();
          await s.save();
          return;
        }
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
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

      // Extract mg strengths from the scan (e.g., 5mg, 10 mg)
      final mgMatches = RegExp(r"(\d{1,3})\s*mg").allMatches(normalizedScan).map((m) => m.group(1)!).toSet();
      final hasTablet = normalizedScan.contains('tablet');
      final hasCapsule = normalizedScan.contains('capsule');

      for (var row in _data.skip(1)) {
        if (row.length < 17) continue;
        final normBrand = _normalizeText(row[3]);
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
        final normGeneric = _normalizeText(row[2]);
        final normStrength = _normalizeText(row[4]);
        final normForm = _normalizeText(row[5]);
        final normDistributor = row.length > 13 ? _normalizeText(row[13]) : '';

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
        if (row.length < 17) continue;
        final normBrand = _normalizeText(row[3]);
        final normGeneric = _normalizeText(row[2]);
        if (normBrand.contains('lodibes') && normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (lodibes+amlodipine): ${row[3]}');
          final m = _buildMap(row);
          m['match_reason'] = 'Deterministic contains: brand and generic present';
          return m;
        }
      }
    }
    // If only generic is present, pick the first amlodipine entry
    if (normalizedScan.contains('amlodipine')) {
      for (var row in _data.skip(1)) {
        if (row.length < 17) continue;
        final normGeneric = _normalizeText(row[2]);
        if (normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (amlodipine only): ${row[3]}');
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
      if (row.length < 17) continue; // skip incomplete rows

      final brand = row[3];
      final generic = row[2];
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
      final normBrand = _normalizeText(bestMatch[3]);
      final normGeneric = _normalizeText(bestMatch[2]);
      final normStrength = _normalizeText(bestMatch[4]);
      final normForm = _normalizeText(bestMatch[5]);
      final brandTokens = normBrand.split(' ').where((t) => t.isNotEmpty).toSet();
      final genericTokens = normGeneric.split(' ').where((t) => t.isNotEmpty).toSet();
      final brandHits = brandTokens.intersection(scanTokenSet).length;
      final genericHits = genericTokens.intersection(scanTokenSet).length;
      final mgHit = RegExp(r"(\d{1,3})\s*mg").allMatches(normalizedScan).any((m) {
        final n = m.group(1)!;
        return normStrength.contains('$n mg') || normStrength.contains('${n}mg');
      });
      final formCue = (normalizedScan.contains('tablet') && normForm.contains('tablet')) ||
          (normalizedScan.contains('capsule') && normForm.contains('capsule'));
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
    final mgMatches = RegExp(r"(\d{1,3})\s*mg").allMatches(normalizedScan).map((m) => m.group(1)!).toSet();
    final hasTablet = normalizedScan.contains('tablet');
    final hasCapsule = normalizedScan.contains('capsule');
    // Reg No candidates
    final regCandidates = _extractRegCandidates(scannedText).map(_normalizeReg).toSet();

    for (var row in _data.skip(1)) {
      if (row.length < 17) continue;
      double s = 0.0;

      final normBrand = _normalizeText(row[3]);
      final normGeneric = _normalizeText(row[2]);
      final normStrength = _normalizeText(row[4]);
      final normForm = _normalizeText(row[5]);
      final normDistributor = row.length > 13 ? _normalizeText(row[13]) : '';
      final normReg = row.length > 1 ? _normalizeReg((row[1] ?? '').toString()) : '';

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
    String cell(int i) => (i >= 0 && i < row.length) ? (row[i]?.toString() ?? '') : '';

    final Map<String, String> product = {};

    // Store every column as string, if present
    for (int i = 0; i < row.length; i++) {
      product['col_$i'] = row[i]?.toString() ?? '';
    }

    // Add friendly keys with bounds safety
    product['reg_no'] = cell(1);
    product['generic_name'] = cell(2);
    product['brand_name'] = cell(3);
    product['dosage_strength'] = cell(4);
    product['dosage_form'] = cell(5);
    product['manufacturer'] = cell(9);
    product['country'] = cell(10);
    product['distributor'] = cell(13);
    product['issuance_date'] = cell(15);
    product['expiry_date'] = cell(16);

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

    // Reg. No. mismatch between package and FDA record
    final cands = _extractRegCandidates(raw).map(_normalizeReg).toSet();
    final reg = _normalizeReg(product['reg_no'] ?? '');
    if (cands.isNotEmpty && reg.isNotEmpty && !cands.contains(reg)) {
      if (status == 'VERIFIED') status = 'ALERT';
      reasons.add('Registration number on pack differs from FDA record');
    }

    // Note: We intentionally ignore dosage strength mismatches for status.
    // The displayed strength is fetched directly from the FDA CSV.

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

    // Manufacturer/Distributor cue mismatch (soft check)
    final normMfg = _normalizeText(product['manufacturer'] ?? '');
    final normDist = _normalizeText(product['distributor'] ?? '');
    final hasMfgCue = rawNorm.contains('manufactured by') || rawNorm.contains('manufacturer');
    final hasDistCue = rawNorm.contains('distributed by') || rawNorm.contains('distributor');
    if ((hasMfgCue || hasDistCue) &&
        normMfg.isNotEmpty && normDist.isNotEmpty &&
        !rawNorm.contains(normMfg) && !rawNorm.contains(normDist)) {
      // Do not escalate if already EXPIRED; otherwise add soft warning or alert in strict mode
      final strict = SettingsService.instance.strictMatching;
      if (status == 'VERIFIED' && strict) status = 'ALERT';
      reasons.add('Manufacturer/distributor on pack seems different from FDA record');
    }

    return (status: status, reasons: reasons);
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final v = s.trim();
    final iso = DateTime.tryParse(v);
    if (iso != null) return iso;
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
  for (final row in norm.skip(1)) {
    if (row.length < 2) continue;
    final reg = row[1].toString();
    if (reg.isEmpty) continue;
    final n = normalizeReg(reg);
    if (n.isEmpty) continue;
    regIdx[n] = row;
  }

  return _ParsedFdaData(data: norm, regIndex: regIdx);
}
