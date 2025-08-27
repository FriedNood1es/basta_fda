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
      final parsedData = const CsvToListConverter(eol: '\n').convert(rawData);

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
    final scanTokens = normalizedScan.split(' ');

    double bestScore = 0.0;
    List<dynamic>? bestMatch;

    for (var row in _data.skip(1)) {
      if (row.length < 17) continue; // skip incomplete rows

      final brand = row[3];
      final generic = row[2];

      double tokenMatchScore = 0.0;

      // Compare every token in scanned text with brand & generic name
      for (var token in scanTokens) {
        for (var b in brand.split(' ')) {
          if (StringSimilarity.compareTwoStrings(token, b) > 0.8) {
            tokenMatchScore += 1.0;
          }
        }
        for (var g in generic.split(' ')) {
          if (StringSimilarity.compareTwoStrings(token, g) > 0.8) {
            tokenMatchScore += 0.8;
          }
        }
      }

      if (tokenMatchScore > bestScore) {
        bestScore = tokenMatchScore;
        bestMatch = row;
      }
    }

    // ✅ Only accept if score is meaningful
    if (bestMatch != null && bestScore >= 1.5) {
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
