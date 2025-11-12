import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:basta_fda/data/packaging_trained_products.dart';

class ImagePrediction {
  final String category;
  final String productName;
  final double confidence;
  final String source;
  final String? verdict;
  final double? authenticScore;
  final double? suspiciousScore;

  const ImagePrediction({
    required this.category,
    required this.productName,
    required this.confidence,
    this.source = 'tflite',
    this.verdict,
    this.authenticScore,
    this.suspiciousScore,
  });

  Map<String, String> toMap() {
    final map = <String, String>{
      'category': category,
      'product': productName,
      'confidence': confidence.toStringAsFixed(2),
      'source': source,
    };
    if (verdict != null && verdict!.isNotEmpty) {
      map['verdict'] = verdict!;
    }
    if (authenticScore != null) {
      map['authenticScore'] = authenticScore!.toStringAsFixed(4);
    }
    if (suspiciousScore != null) {
      map['suspiciousScore'] = suspiciousScore!.toStringAsFixed(4);
    }
    return map;
  }
}

class PackagingImageClassifier {
  PackagingImageClassifier._();
  static final PackagingImageClassifier instance =
      PackagingImageClassifier._();

  Interpreter? _interpreter;
  List<String>? _labels;
  int _inputHeight = 224;
  int _inputWidth = 224;
  int _inputChannels = 3;
  Future<void>? _loading;

  static const double _minConfidence = 0.45;

  Future<void> _ensureLoaded() async {
    if (_interpreter != null && _labels != null) return;
    _loading ??= _loadResources();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadResources() async {
    try {
      try {
        _interpreter =
            await Interpreter.fromAsset('assets/model_unquant.tflite');
      } on Exception {
        _interpreter = await Interpreter.fromAsset('model_unquant.tflite');
      }
      final inputTensor = _interpreter!.getInputTensor(0);
      final shape = inputTensor.shape;
      if (shape.length >= 4) {
        _inputHeight = shape[1];
        _inputWidth = shape[2];
        _inputChannels = shape[3];
      }
      final rawLabels = await rootBundle.loadString('assets/labels.txt');
      _labels = rawLabels
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) {
        final parts = line.split(RegExp(r'\s+'));
        return parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;
      }).toList();
    } catch (e, stack) {
      debugPrint('Failed to load image classifier: $e');
      debugPrint('$stack');
      _interpreter = null;
      _labels = null;
    }
  }

  Future<ImagePrediction?> classify({
    required String rawText,
    String? additionalText,
    String? imagePath,
  }) async {
    final normalized = _normalizeText(rawText, additionalText);

    await _ensureLoaded();

    if (_interpreter == null || _labels == null || imagePath == null) {
      return _classifyFromText(normalized);
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return _classifyFromText(normalized);
      }
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return _classifyFromText(normalized);
      }
      final input = _convertToInput(decoded);
      final output =
          List.generate(1, (_) => List<double>.filled(_labels!.length, 0));

      _interpreter!.run(input, output);
      final scores = output.first;
      final bestIndex = _argMax(scores);
      if (bestIndex < 0) {
        return _classifyFromText(normalized);
      }
      final confidence = scores[bestIndex];
      if (confidence.isNaN || confidence < _minConfidence) {
        return _classifyFromText(normalized);
      }

      double authenticScore = 0;
      double suspiciousScore = 0;
      for (var i = 0; i < scores.length && i < _labels!.length; i++) {
        final label = _parseLabel(_labels![i]);
        final value = scores[i].isNaN ? 0.0 : scores[i];
        if (label.isSuspicious) {
          suspiciousScore += value;
        } else {
          authenticScore += value;
        }
      }
      final sum = authenticScore + suspiciousScore;
      if (sum > 0) {
        authenticScore /= sum;
        suspiciousScore /= sum;
      }

      final labelInfo = _parseLabel(_labels![bestIndex]);
      final verdictText = labelInfo.isSuspicious
          ? 'Suspicious ${labelInfo.category.toLowerCase()} packaging'
          : 'Authentic ${labelInfo.category.toLowerCase()} packaging';

      return ImagePrediction(
        category: labelInfo.category,
        productName: verdictText,
        confidence: confidence,
        source: 'tflite',
        verdict: labelInfo.isSuspicious ? 'suspicious' : 'authentic',
        authenticScore: authenticScore.clamp(0.0, 1.0).toDouble(),
        suspiciousScore: suspiciousScore.clamp(0.0, 1.0).toDouble(),
      );
    } catch (e, stack) {
      debugPrint('Image classification error: $e');
      debugPrint('$stack');
      return _classifyFromText(normalized);
    }
  }

  List<List<List<List<double>>>> _convertToInput(img.Image image) {
    final resized = img.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );
    return [
      List.generate(
        _inputHeight,
        (y) => List.generate(
          _inputWidth,
          (x) {
            final pixel = resized.getPixel(x, y);
            final r = pixel.rNormalized.toDouble();
            final g = pixel.gNormalized.toDouble();
            final b = pixel.bNormalized.toDouble();
            if (_inputChannels <= 1) {
              final gray = (r + g + b) / 3;
              return [gray];
            }
            final values = [r, g, b];
            if (_inputChannels >= values.length) {
              return values;
            }
            return values.sublist(0, _inputChannels);
          },
        ),
      ),
    ];
  }

  ImagePrediction? _classifyFromText(String normalized) {
    for (final sample in PackagingCoverage.products) {
      if (sample.matchesNormalizedText(normalized)) {
        return ImagePrediction(
          category: _titleCase(sample.category),
          productName: sample.name,
          confidence: 0.92,
          source: 'text-heuristic',
          verdict: null,
        );
      }
    }

    if (normalized.contains('tablet') || normalized.contains('capsule')) {
      return ImagePrediction(
        category: 'Medicine',
        productName: 'Unrecognized tablet',
        confidence: 0.55,
        source: 'text-heuristic',
        verdict: null,
      );
    }
    if (normalized.contains('vitamin') || normalized.contains('supplement')) {
      return ImagePrediction(
        category: 'Supplement',
        productName: 'Unrecognized supplement',
        confidence: 0.6,
        source: 'text-heuristic',
        verdict: null,
      );
    }
    if (normalized.contains('cream') ||
        normalized.contains('lotion') ||
        normalized.contains('facial')) {
      return ImagePrediction(
        category: 'Cosmetic',
        productName: 'Unrecognized cosmetic',
        confidence: 0.58,
        source: 'text-heuristic',
        verdict: null,
      );
    }
    if (normalized.contains('drink') ||
        normalized.contains('snack') ||
        normalized.contains('chocolate')) {
      return ImagePrediction(
        category: 'Food',
        productName: 'Unrecognized food item',
        confidence: 0.52,
        source: 'text-heuristic',
        verdict: null,
      );
    }
    return null;
  }

  String _normalizeText(String raw, String? additional) {
    final buffer = StringBuffer(raw.toLowerCase());
    if (additional != null && additional.isNotEmpty) {
      buffer.write(' ');
      buffer.write(additional.toLowerCase());
    }
    return buffer.toString();
  }

  int _argMax(List<double> values) {
    var bestScore = double.negativeInfinity;
    var bestIndex = -1;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value.isNaN) continue;
      if (value > bestScore) {
        bestScore = value;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  _LabelInfo _parseLabel(String raw) {
    final clean = raw.trim();
    final parts = clean.split(RegExp(r'[_\s]+'));
    final category = parts.isNotEmpty ? parts.first : 'unknown';
    final status = parts.length > 1 ? parts.last : 'authentic';
    return _LabelInfo(
      category: _titleCase(category),
      status: status.toLowerCase(),
    );
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }
}

class _LabelInfo {
  final String category;
  final String status;

  const _LabelInfo({required this.category, required this.status});

  bool get isSuspicious => status.contains('suspicious');
}
