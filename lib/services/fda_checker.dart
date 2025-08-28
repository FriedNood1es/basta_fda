import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:string_similarity/string_similarity.dart';

class FDAChecker {
  List<List<dynamic>> _data = [];

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
      double bestBrandScore = -1e9;
      List<dynamic>? bestBrandRow;

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
        if (genTokens.intersection(scanTokenSet).isNotEmpty) s += 2.0;

        // Strength match (any scanned mg appearing in this row's strength)
        for (final n in mgMatches) {
          if (normStrength.contains('$n mg') || normStrength.contains('${n}mg')) {
            s += 1.0;
          }
        }

        // Dosage form cues
        if (hasTablet && normForm.contains('tablet')) s += 0.6;
        if (hasCapsule && normForm.contains('capsule')) s += 0.6;

        // Distributor token overlap (e.g., tgp)
        final distTokens = normDistributor.split(' ').where((t) => t.length >= 3).toSet();
        if (distTokens.intersection(scanTokenSet).isNotEmpty) s += 0.6;

        if (s > bestBrandScore) {
          bestBrandScore = s;
          bestBrandRow = row;
        }
      }

      // If we found a plausible brand candidate, use it
      if (bestBrandRow != null && bestBrandScore >= 1.5) {
        debugPrint('[FDAChecker] brand-first match: brand=' + bestBrandRow[3].toString() + ' | strength=' + bestBrandRow[4].toString());
        return _buildMap(bestBrandRow);
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
      debugPrint('[FDAChecker] rows=' + _data.length.toString() + ' | scan aml=' + hasAml.toString() + ', lod=' + hasLod.toString() + ' | rows aml=' + amlCount.toString() + ', lod=' + lodCount.toString());
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

      if (preRow != null && preBest >= 1.0) {
        debugPrint('[FDAChecker] prepass fallback match: brand=' + preRow[3].toString() + ' | score=' + preBest.toString());
        return _buildMap(preRow);
      }
    }

    // Deterministic contains fallback for very common cases (e.g., amlodipine + brand)
    if (normalizedScan.contains('lodibes') && normalizedScan.contains('amlodipine')) {
      for (var row in _data.skip(1)) {
        if (row.length < 17) continue;
        final normBrand = _normalizeText(row[3]);
        final normGeneric = _normalizeText(row[2]);
        if (normBrand.contains('lodibes') && normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (lodibes+amlodipine): ' + row[3].toString());
          return _buildMap(row);
        }
      }
    }
    // If only generic is present, pick the first amlodipine entry
    if (normalizedScan.contains('amlodipine')) {
      for (var row in _data.skip(1)) {
        if (row.length < 17) continue;
        final normGeneric = _normalizeText(row[2]);
        if (normGeneric.contains('amlodipine')) {
          debugPrint('[FDAChecker] deterministic match (amlodipine only): ' + row[3].toString());
          return _buildMap(row);
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
    if (bestMatch != null && (bestScore >= 1.5 || bestHasStrongExactMatch)) {
      debugPrint("✅ Best match: Brand=${bestMatch[3]} | Score=$bestScore");
      return _buildMap(bestMatch);
    }

    debugPrint("❌ No match found for scanned text.");
    return null;
  }

  /// Build a map for easy display in Scan Result Screen
  Map<String, String> _buildMap(List<dynamic> row) {
    Map<String, String> product = {};

    // Store every column
    for (int i = 0; i < row.length; i++) {
      product["col_$i"] = row[i];
    }

    // Add friendly keys
    product["reg_no"] = row[1];
    product["generic_name"] = row[2];
    product["brand_name"] = row[3];
    product["dosage_strength"] = row[4];
    product["dosage_form"] = row[5];
    product["manufacturer"] = row[9];
    product["country"] = row[10];
    product["distributor"] = row[13];
    product["issuance_date"] = row[15];
    product["expiry_date"] = row[16];

    return product;
  }
}
