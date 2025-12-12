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
  static final PackagingImageClassifier instance = PackagingImageClassifier._();

  Interpreter? _interpreter;
  List<String>? _labels;
  String? _loadedModelAsset;
  int _outputClassCount = 0;
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
      final modelCandidates = [
        'assets/food_model.tflite',
        'assets/model_unquant.tflite',
        'model_unquant.tflite',
      ];
      Interpreter? interpreter;
      String? loadedAsset;
      final errors = <Object>[];
      for (final asset in modelCandidates) {
        try {
          interpreter = await Interpreter.fromAsset(asset);
          loadedAsset = asset;
          debugPrint('Loaded packaging model: $asset');
          break;
        } catch (e, stack) {
          errors.add(e);
          debugPrint('Failed to load packaging model $asset: $e');
          final opHint = _describeUnsupportedOp(e);
          if (asset.contains('food_model') && opHint != null) {
            debugPrint(
              'food_model.tflite requires a newer TensorFlow Lite runtime ($opHint). Falling back.',
            );
          }
          debugPrint('$stack');
        }
      }
      if (interpreter == null || loadedAsset == null) {
        throw (errors.isNotEmpty
            ? errors.last
            : Exception('Unable to load packaging model asset'));
      }
      _interpreter = interpreter;
      _loadedModelAsset = loadedAsset;
      if (!loadedAsset.contains('food_model')) {
        final reason = errors.isNotEmpty
            ? errors.last.toString()
            : 'unknown error';
        debugPrint(
          'Packaging classifier fell back to legacy model_unquant ($reason).',
        );
      }
      final inputTensor = _interpreter!.getInputTensor(0);
      final shape = inputTensor.shape;
      if (shape.length >= 4) {
        _inputHeight = shape[1];
        _inputWidth = shape[2];
        _inputChannels = shape[3];
      }
      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      if (outputShape.isNotEmpty) {
        _outputClassCount = outputShape.last;
      } else if (_labels != null && _labels!.isNotEmpty) {
        _outputClassCount = _labels!.length;
      }
      final rawLabels = await rootBundle.loadString('assets/labels.txt');
      _labels = rawLabels
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) {
            final parts = line.split(RegExp(r'\s+'));
            return parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;
          })
          .toList();
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

    if (_loadedModelAsset != null && imagePath != null) {
      debugPrint('Packaging scan using model: $_loadedModelAsset');
    }

    if (_interpreter == null || imagePath == null) {
      return _classifyFromText(normalized);
    }

    final classCount = _outputClassCount > 0
        ? _outputClassCount
        : (_labels?.length ?? 0);
    if (classCount <= 0) {
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
      final output = List.generate(
        1,
        (_) => List<double>.filled(classCount, 0),
      );

      _interpreter!.run(input, output);
      final scores = output.first;
      debugPrint('Packaging logits: ' + scores.toString());
      final bestIndex = _argMax(scores);
      if (bestIndex < 0) {
        return _classifyFromText(normalized);
      }
      final confidence = scores[bestIndex];
      if (confidence.isNaN || confidence < _minConfidence) {
        return _classifyFromText(normalized);
      }

      final labelInfo = _labelInfoForIndex(bestIndex);
      final authenticity = confidence.clamp(0.0, 1.0).toDouble();
      final suspicious = (1 - authenticity).clamp(0.0, 1.0).toDouble();
      final productName = labelInfo.category;
      final matchPercent = (authenticity * 100).toStringAsFixed(1);
      final verdictText = '$productName ($matchPercent% match)';
      final verdictValue = suspicious > authenticity
          ? 'suspicious'
          : 'authentic';

      return ImagePrediction(
        category: productName,
        productName: productName,
        confidence: confidence,
        source: 'tflite',
        verdict: verdictValue,
        authenticScore: authenticity,
        suspiciousScore: suspicious,
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
        (y) => List.generate(_inputWidth, (x) {
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
        }),
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
    if (clean.isEmpty) {
      return const _LabelInfo(category: 'Unknown', status: 'authentic');
    }
    final tokens = clean
        .split(RegExp(r'[_\s]+'))
        .where((token) => token.isNotEmpty)
        .toList();
    var status = 'authentic';
    if (tokens.isNotEmpty) {
      final last = tokens.last.toLowerCase();
      if (last == 'authentic' || last == 'suspicious') {
        status = last;
        tokens.removeLast();
      }
    }
    final categoryTokens = tokens.isEmpty ? [clean] : tokens;
    final category = _titleCase(categoryTokens.join(' '));
    return _LabelInfo(category: category, status: status);
  }

  _LabelInfo _labelInfoForIndex(int index) {
    if (_labels != null && index >= 0 && index < _labels!.length) {
      return _parseLabel(_labels![index]);
    }
    final category = _outputClassCount > 0 ? 'Class ${index + 1}' : 'Unknown';
    return _LabelInfo(category: category, status: 'authentic');
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    final words = input.split(' ');
    return words
        .map((word) {
          if (word.isEmpty) return word;
          if (word.length == 1) {
            return word.toUpperCase();
          }
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String? _describeUnsupportedOp(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('fully_connected') &&
        message.contains("version '12'")) {
      return 'FULLY_CONNECTED v12';
    }
    return null;
  }
}

class _LabelInfo {
  final String category;
  final String status;

  const _LabelInfo({required this.category, required this.status});

  bool get isSuspicious => status.contains('suspicious');
}
