import 'dart:io';

import 'package:basta_fda/services/image_classifier.dart';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

class EvalSample {
  final String? imagePath;
  final String extractedText;
  final String expectedVerdict;

  EvalSample({
    required this.imagePath,
    required this.extractedText,
    required this.expectedVerdict,
  });
}

Future<List<EvalSample>> loadEvalSamples() async {
  try {
    final csvRaw =
        await rootBundle.loadString('test_assets/packaging_eval.csv');
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvRaw);
    if (rows.isEmpty) return [];

    final header = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    final imageIdx = header.indexOf('image_path');
    final textIdx = header.indexOf('extracted_text');
    final verdictIdx = header.indexOf('expected_verdict');

    return rows.skip(1).where((row) => row.isNotEmpty).map((row) {
      String? imagePath;
      if (imageIdx >= 0 && imageIdx < row.length) {
        final value = row[imageIdx].toString().trim();
        if (value.isNotEmpty) imagePath = value;
      }
      final text =
          textIdx >= 0 && textIdx < row.length ? row[textIdx].toString() : '';
      final verdict = verdictIdx >= 0 && verdictIdx < row.length
          ? row[verdictIdx].toString()
          : '';
      return EvalSample(
        imagePath: imagePath,
        extractedText: text.trim(),
        expectedVerdict: verdict.trim().toLowerCase(),
      );
    }).where((sample) {
      return sample.extractedText.isNotEmpty ||
          (sample.imagePath != null && sample.imagePath!.isNotEmpty);
    }).toList();
  } catch (_) {
    return [];
  }
}

Directory? _tempAssetDir;

Future<String?> _materializeAsset(String? assetPath) async {
  if (assetPath == null || assetPath.isEmpty) return null;
  try {
    final data = await rootBundle.load(assetPath);
    _tempAssetDir ??= await Directory.systemTemp.createTemp('packaging_eval_');
    final file = File(
        '${_tempAssetDir!.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      flush: true,
    );
    return file.path;
  } catch (_) {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const strictVerdictCheck =
      bool.fromEnvironment('STRICT_PACKAGING_EVAL', defaultValue: false);

  late List<EvalSample> samples;

  setUpAll(() async {
    samples = await loadEvalSamples();
  });

  test('loads packaging eval CSV', () {
    expect(samples, isNotEmpty,
        reason: 'Add rows to test_assets/packaging_eval.csv');
  });

  test('classifies packaging eval samples', () async {
    final classifier = PackagingImageClassifier.instance;

    for (final sample in samples) {
      final imagePath = await _materializeAsset(sample.imagePath);
      final prediction = await classifier.classify(
        rawText: sample.extractedText,
        imagePath: imagePath,
      );

      if (strictVerdictCheck && sample.expectedVerdict.isNotEmpty) {
        final actual = prediction?.verdict?.toLowerCase();
        expect(
          actual,
          sample.expectedVerdict,
          reason: 'Sample: ${sample.imagePath ?? '[text-only]'}',
        );
      } else {
        // Smoke-check that classification completes without throwing.
        expect(prediction, anyOf(isNull, isA<ImagePrediction>()));
      }
    }
  });

  test('packaging classifier accuracy on labeled evaluation set', () async {
    final classifier = PackagingImageClassifier.instance;

    final labeled =
        samples.where((s) => s.expectedVerdict.isNotEmpty).toList();
    expect(labeled, isNotEmpty,
        reason: 'Add expected_verdict values in packaging_eval.csv');

    int correct = 0;
    final total = labeled.length;

    for (final sample in labeled) {
      final imagePath = await _materializeAsset(sample.imagePath);
      if (sample.imagePath != null && sample.imagePath!.isNotEmpty) {
        expect(imagePath, isNotNull,
            reason: 'Missing image at ${sample.imagePath}');
      }

      final prediction = await classifier.classify(
        rawText: sample.extractedText,
        imagePath: imagePath,
      );
      final predicted = prediction?.verdict?.toLowerCase() ?? '';

      if (predicted == sample.expectedVerdict) {
        correct++;
      } else {
        // Optional: log mismatches for debugging
        // ignore: avoid_print
        print(
          'MISCLASSIFIED: expected=${sample.expectedVerdict}, '
          'got=$predicted, image=${sample.imagePath}, text="${sample.extractedText}"',
        );
      }
    }

    final accuracy = total == 0 ? 0.0 : correct / total;
    // ignore: avoid_print
    print(
      'Accuracy: $correct / $total = ${(accuracy * 100).toStringAsFixed(1)}%',
    );

    const minAccuracy = 0.80; // 80%
    expect(
      accuracy >= minAccuracy,
      isTrue,
      reason:
          'Accuracy ${accuracy.toStringAsFixed(3)} is below threshold $minAccuracy',
    );
  });
}
