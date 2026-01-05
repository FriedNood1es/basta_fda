import 'dart:convert';
import 'dart:io';

import 'package:basta_fda/models/scan_verdict.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/services/image_classifier.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

const _evalCsvAsset = 'test_assets/eval/verification_eval.csv';
const _positiveLabel = 'VERIFIED';
const _negativeLabel = 'NOT_VERIFIED';
const bool _strictEval =
    bool.fromEnvironment('STRICT_VERIFICATION_EVAL', defaultValue: false);

class VerificationEvalSample {
  final String assetPath;
  final String expectedLabel;
  final String? regOverride;
  final bool skipRegistration;
  final PackagingModelCategory? categoryOverride;

  VerificationEvalSample({
    required this.assetPath,
    required this.expectedLabel,
    this.regOverride,
    this.skipRegistration = false,
    this.categoryOverride,
  });
}

Future<List<VerificationEvalSample>> loadVerificationSamples() async {
  try {
    final csvRaw = await rootBundle.loadString(_evalCsvAsset);
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvRaw);
    if (rows.isEmpty) return [];
    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    final imageIdx = header.indexOf('image_path');
    final verdictIdx = header.indexOf('expected_verification');
    final regIdx = header.indexOf('reg_override');
    final categoryIdx = header.indexOf('category');
    if (imageIdx < 0 || verdictIdx < 0) {
      throw const FormatException(
        'CSV header must contain image_path and expected_verification columns.',
      );
    }
    final samples = <VerificationEvalSample>[];
    for (final row in rows.skip(1)) {
      if (row.isEmpty) continue;
      final rawPath =
          imageIdx < row.length ? row[imageIdx].toString().trim() : '';
      final rawExpected =
          verdictIdx < row.length ? row[verdictIdx].toString().trim() : '';
      if (rawPath.isEmpty || rawExpected.isEmpty) continue;
      final normalizedPath = _normalizeAssetPath(rawPath);
      final normalizedExpected = rawExpected.toUpperCase() == _positiveLabel
          ? _positiveLabel
          : _negativeLabel;
      String? regOverride;
      bool skipRegistration = false;
      if (regIdx >= 0 && regIdx < row.length) {
        final rawReg = row[regIdx].toString().trim();
        if (rawReg.isNotEmpty) {
          if (rawReg.toUpperCase() == 'SKIP') {
            skipRegistration = true;
          } else {
            regOverride = rawReg;
          }
        }
      }
      PackagingModelCategory? categoryOverride;
      if (categoryIdx >= 0 && categoryIdx < row.length) {
        final rawCategory = row[categoryIdx].toString().trim();
        if (rawCategory.isNotEmpty) {
          categoryOverride = _categoryFromName(rawCategory);
        }
      }
      samples.add(
        VerificationEvalSample(
          assetPath: normalizedPath,
          expectedLabel: normalizedExpected,
          regOverride: regOverride,
          skipRegistration: skipRegistration,
          categoryOverride: categoryOverride,
        ),
      );
    }
    return samples;
  } catch (e) {
    debugPrint('Verification eval CSV not found or invalid: $e');
    return [];
  }
}

String _normalizeAssetPath(String rawPath) {
  var path = rawPath.replaceAll('\\\\', '/').trim();
  path = path.replaceFirst(RegExp(r'^(\./)+'), '');
  if (path.startsWith('/')) {
    path = path.substring(1);
  }
  if (!path.startsWith('test_assets/')) {
    if (path.startsWith('eval/')) {
      path = 'test_assets/$path';
    } else {
      path = 'test_assets/eval/$path';
    }
  }
  return path;
}

Directory? _tempAssetDir;

Future<String?> _materializeAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    _tempAssetDir ??=
        await Directory.systemTemp.createTemp('verification_eval_');
    final file = File('${_tempAssetDir!.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      flush: true,
    );
    return file.path;
  } catch (e) {
    debugPrint('Unable to materialize $assetPath: $e');
    return null;
  }
}

class VerificationDecision {
  final String status;
  final RegistrationStatus registrationStatus;
  final ImageCheckResult imageResult;
  final Map<String, String>? product;
  final String rawText;
  final String? regNumber;
  final String predictedLabel;

  VerificationDecision({
    required this.status,
    required this.registrationStatus,
    required this.imageResult,
    required this.product,
    required this.rawText,
    required this.regNumber,
    required this.predictedLabel,
  });
}

class VerificationEvaluator {
  VerificationEvaluator({
    required this.fdaChecker,
    required this.textRecognizer,
  });

  final FDAChecker fdaChecker;
  final TextRecognizer textRecognizer;
  final PackagingImageClassifier _classifier =
      PackagingImageClassifier.instance;

  Future<VerificationDecision> evaluate(VerificationEvalSample sample) async {
    final assetPath = sample.assetPath;
    final filePath = await _materializeAsset(assetPath);
    if (filePath == null) {
      return VerificationDecision(
        status: 'NOT FOUND',
        registrationStatus: RegistrationStatus.unregistered,
        imageResult: const ImageCheckResult(status: ImageCheckStatus.failed),
        product: null,
        rawText: '',
        regNumber: null,
        predictedLabel: _negativeLabel,
      );
    }

    String rawText = '';
    String? extractedReg;
    if (sample.regOverride != null && sample.regOverride!.isNotEmpty) {
      rawText = sample.regOverride!.trim();
      extractedReg = rawText;
    } else {
      final inputImage = InputImage.fromFilePath(filePath);
      try {
        final recognizedText = await textRecognizer.processImage(inputImage);
        rawText = recognizedText.text.trim();
      } on MissingPluginException catch (e) {
        debugPrint('TextRecognizer unavailable: $e');
      }
      extractedReg = _extractRegNumber(rawText);
    }

    final prediction = await _classifier.classify(
      rawText: rawText,
      imagePath: filePath,
      category: sample.categoryOverride ?? _inferCategory(assetPath),
    );
    final imageResult = _predictionToResult(prediction);

    Map<String, String>? product;
    if (!sample.skipRegistration) {
      product = fdaChecker.findByRegNo(rawText);
      final regLike = _looksLikeRegistrationQuery(rawText);
      if (product == null && !regLike) {
        product = await fdaChecker.findProductDetailsWithExplainAsync(rawText);
      }
    } else {
      product = null;
    }

    String status;
    RegistrationStatus registrationStatus;
    if (product != null) {
      final eval = fdaChecker.evaluateScan(raw: rawText, product: product);
      status = eval.status;
      if (eval.reasons.isNotEmpty) {
        product['verification_reasons'] = eval.reasons.join('\n');
      }
      registrationStatus = RegistrationStatus.registered;
    } else {
      registrationStatus = sample.skipRegistration
          ? RegistrationStatus.skipped
          : RegistrationStatus.unregistered;
      status = imageResult.status == ImageCheckStatus.recognized
          ? 'IMAGE_ONLY'
          : 'NOT FOUND';
    }

    final label = _decideVerdict(
      status: status,
      registrationStatus: registrationStatus,
      imageResult: imageResult,
    );

    return VerificationDecision(
      status: status,
      registrationStatus: registrationStatus,
      imageResult: imageResult,
      product: product,
      rawText: rawText,
      regNumber: extractedReg,
      predictedLabel: label,
    );
  }
}

bool _looksLikeRegistrationQuery(String raw) {
  return _regCodePattern.hasMatch(raw) || _labeledRegPattern.hasMatch(raw);
}

final _regCodePattern =
    RegExp(r'\b[A-Za-z]{2,4}-\d{3,6}(?:-\d{2,4})?\b');
final _labeledRegPattern = RegExp(
  r'\breg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*[A-Za-z]{2,4}-\d{3,6}(?:-\d{2,4})?\b',
  caseSensitive: false,
);

PackagingModelCategory? _categoryFromName(String name) {
  final normalized = name.trim().toLowerCase();
  switch (normalized) {
    case 'medicine':
      return PackagingModelCategory.medicine;
    case 'food':
      return PackagingModelCategory.food;
    case 'cosmetics':
      return PackagingModelCategory.cosmetics;
    case 'supplements':
      return PackagingModelCategory.supplements;
    default:
      return null;
  }
}

PackagingModelCategory _inferCategory(String path) {
  final lower = path.toLowerCase();
  if (lower.contains('cosmetic')) return PackagingModelCategory.cosmetics;
  if (lower.contains('supplement')) return PackagingModelCategory.supplements;
  if (lower.contains('food')) return PackagingModelCategory.food;
  return PackagingModelCategory.medicine;
}

ImageCheckResult _predictionToResult(ImagePrediction? prediction) {
  if (prediction == null) {
    return const ImageCheckResult(status: ImageCheckStatus.unrecognized);
  }
  return ImageCheckResult(
    status: ImageCheckStatus.recognized,
    info: prediction.toMap(),
  );
}

String? _extractRegNumber(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final regPattern = RegExp(
    '(${FDAChecker.regFlexiblePattern})',
    caseSensitive: false,
  );
  final verbosePattern = RegExp(
    'reg(?:istration)?\\.?\\s*(?:no\\.?|number)\\s*[:#-]?\\s*(${FDAChecker.regFlexiblePattern})',
    caseSensitive: false,
  );
  final verbose = verbosePattern.firstMatch(trimmed);
  if (verbose != null) return verbose.group(1)?.toUpperCase();
  final direct = regPattern.firstMatch(trimmed);
  if (direct != null) return direct.group(1)?.toUpperCase();
  return null;
}

String _decideVerdict({
  required String status,
  required RegistrationStatus registrationStatus,
  required ImageCheckResult imageResult,
}) {
  final normalized = status.trim().toUpperCase();
  final imageVerdict = (imageResult.info?['verdict'] ?? '').toLowerCase();
  final packagingAuthentic =
      imageResult.status == ImageCheckStatus.recognized &&
          (imageVerdict.isEmpty || imageVerdict == 'authentic');

  switch (normalized) {
    case 'RECOGNIZED':
      return _positiveLabel;
    case 'UNRECOGNIZED':
    case 'EXPIRED':
    case 'NOT FOUND':
      return _negativeLabel;
    case 'IMAGE_ONLY':
      return packagingAuthentic ? _positiveLabel : _negativeLabel;
  }

  if (registrationStatus == RegistrationStatus.registered) {
    return _positiveLabel;
  }
  if (registrationStatus == RegistrationStatus.skipped && packagingAuthentic) {
    return _positiveLabel;
  }
  return _negativeLabel;
}

class EvalStats {
  int total = 0;
  int correct = 0;
  int tp = 0;
  int tn = 0;
  int fp = 0;
  int fn = 0;

  void add(String expected, String predicted) {
    total++;
    if (predicted == expected) correct++;
    final expPos = expected == _positiveLabel;
    final predPos = predicted == _positiveLabel;
    if (expPos && predPos) {
      tp++;
    } else if (!expPos && !predPos) {
      tn++;
    } else if (!expPos && predPos) {
      fp++;
    } else {
      fn++;
    }
  }

  String get accuracyPct =>
      _formatPercent(total == 0 ? 0 : correct / total);
  String get precisionPct =>
      _formatPercent((tp + fp) == 0 ? 0 : tp / (tp + fp));
  String get recallPct =>
      _formatPercent((tp + fn) == 0 ? 0 : tp / (tp + fn));
}

String _formatPercent(double value) =>
    '${(value * 100).toStringAsFixed(2)}%';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final fdaChecker = FDAChecker();
  late TextRecognizer textRecognizer;
  late List<VerificationEvalSample> samples;

  setUpAll(() async {
    samples = await loadVerificationSamples();
    await fdaChecker.loadCSVIsolatePreferCache();
    textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  });

  tearDownAll(() async {
    try {
      await textRecognizer.close();
    } catch (e) {
      debugPrint('TextRecognizer close skipped: $e');
    }
    if (_tempAssetDir != null && await _tempAssetDir!.exists()) {
      await _tempAssetDir!.delete(recursive: true);
    }
  });

  test('verification evaluation', () async {
    if (samples.isEmpty) {
      debugPrint(
        'No samples found. Add rows to $_evalCsvAsset to enable the evaluation.',
      );
      return;
    }

    final evaluator = VerificationEvaluator(
      fdaChecker: fdaChecker,
      textRecognizer: textRecognizer,
    );
    final stats = EvalStats();
    final Map<String, EvalStats> categoryStats = {};
    final List<Map<String, dynamic>> sampleResults = [];

    for (final sample in samples) {
      final decision = await evaluator.evaluate(sample);
      final predicted = decision.predictedLabel;
      stats.add(sample.expectedLabel, predicted);
      final catKey = (sample.categoryOverride?.name ??
          _inferCategory(sample.assetPath).name);
      categoryStats[catKey] ??= EvalStats();
      categoryStats[catKey]!.add(sample.expectedLabel, predicted);
      final resultLabel =
          predicted == sample.expectedLabel ? 'PASS' : 'FAIL';
      final imageVerdict =
          decision.imageResult.info?['verdict'] ??
              decision.imageResult.status.label;
      final regNo =
          decision.product?['reg_no'] ?? decision.regNumber ?? 'N/A';
      final brand = decision.product?['brand_name'] ??
          decision.imageResult.info?['product'] ??
          'N/A';

      // ignore: avoid_print
      print(
        '[$resultLabel] image_path=${sample.assetPath} expected=${sample.expectedLabel} '
        'predicted=$predicted status=${decision.status} reg=$regNo '
        'brand=$brand image=$imageVerdict',
      );

      sampleResults.add({
        'image_path': sample.assetPath,
        'expected': sample.expectedLabel,
        'predicted': predicted,
        'status': decision.status,
        'registration_status': decision.registrationStatus.name,
        'image_status': decision.imageResult.status.name,
        'brand': brand,
        'reg_number': regNo,
        'category': catKey,
        'reg_override': sample.regOverride ?? '',
        'skip_registration': sample.skipRegistration,
      });

      if (_strictEval) {
        expect(
          predicted,
          sample.expectedLabel,
          reason: 'Mismatch for ${sample.assetPath}',
        );
      }
    }

    // ignore: avoid_print
    print('--- Verification summary ---');
    // ignore: avoid_print
    print(
      'total=${stats.total} correct=${stats.correct} accuracy=${stats.accuracyPct}',
    );
    // ignore: avoid_print
    print('TP=${stats.tp} TN=${stats.tn} FP=${stats.fp} FN=${stats.fn}');
    // ignore: avoid_print
    print('precision=${stats.precisionPct} recall=${stats.recallPct}');

    if (categoryStats.isNotEmpty) {
      // ignore: avoid_print
      print('--- Accuracy by category ---');
      categoryStats.forEach((key, value) {
        // ignore: avoid_print
        print(
          '$key: total=${value.total} accuracy=${value.accuracyPct} '
          'precision=${value.precisionPct} recall=${value.recallPct}',
        );
      });
    }

    final report = {
      'summary': {
        'total': stats.total,
        'correct': stats.correct,
        'accuracy': stats.accuracyPct,
        'tp': stats.tp,
        'tn': stats.tn,
        'fp': stats.fp,
        'fn': stats.fn,
        'precision': stats.precisionPct,
        'recall': stats.recallPct,
      },
      'categories': categoryStats.map(
        (key, value) => MapEntry(
          key,
          {
            'total': value.total,
            'correct': value.correct,
            'accuracy': value.accuracyPct,
            'tp': value.tp,
            'tn': value.tn,
            'fp': value.fp,
            'fn': value.fn,
            'precision': value.precisionPct,
            'recall': value.recallPct,
          },
        ),
      ),
      'samples': sampleResults,
    };

    Future<File?> _writeReportFile(String relativePath) async {
      try {
        final file = File(relativePath);
        file.parent.createSync(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        return file;
      } catch (e) {
        debugPrint('Failed to write $relativePath: $e');
        return null;
      }
    }

    File? jsonFile = await _writeReportFile('build/verification_eval_results.json');
    if (jsonFile == null) {
      final tempPath =
          '${Directory.systemTemp.path}/verification_eval_results.json';
      jsonFile = await _writeReportFile(tempPath);
      if (jsonFile == null) {
        debugPrint('Unable to persist verification results report.');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
