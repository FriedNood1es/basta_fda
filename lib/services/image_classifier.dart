import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class ImagePrediction {
  final String category;
  final String productName;
  final double confidence;
  final String source;
  final String? verdict;

  const ImagePrediction({
    required this.category,
    required this.productName,
    required this.confidence,
    this.source = 'tflite',
    this.verdict,
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
            final r = img.getRed(pixel) / 255.0;
            final g = img.getGreen(pixel) / 255.0;
            final b = img.getBlue(pixel) / 255.0;
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
    for (final sample in _samples) {
      if (sample.matches(normalized)) {
        return ImagePrediction(
          category: _titleCase(sample.category),
          productName: sample.product,
          confidence: sample.confidence,
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

class _SampleProduct {
  final String category;
  final String product;
  final List<String> keywords;
  final double confidence;

  const _SampleProduct({
    required this.category,
    required this.product,
    required this.keywords,
    this.confidence = 0.92,
  });

  bool matches(String text) => keywords.any(text.contains);
}

const List<_SampleProduct> _samples = [
  _SampleProduct(
    category: 'medicine',
    product: 'Biogesic',
    keywords: ['biogesic', 'paracetamol'],
    confidence: 0.98,
  ),
  _SampleProduct(
    category: 'medicine',
    product: 'Bioflu',
    keywords: ['bioflu', 'phenylephrine'],
  ),
  _SampleProduct(
    category: 'medicine',
    product: 'Alaxan',
    keywords: ['alaxan', 'ibuprofen'],
  ),
  _SampleProduct(
    category: 'medicine',
    product: 'Neozep',
    keywords: ['neozep', 'phenylpropanolamine'],
  ),
  _SampleProduct(
    category: 'medicine',
    product: 'Ascof Lagundi',
    keywords: ['lagundi', 'ascof'],
  ),
  _SampleProduct(
    category: 'food',
    product: 'SkyFlakes Crackers',
    keywords: ['skyflakes', 'cracker'],
  ),
  _SampleProduct(
    category: 'food',
    product: 'Bear Brand Milk',
    keywords: ['bear brand', 'milk'],
  ),
  _SampleProduct(
    category: 'food',
    product: 'Lucky Me Pancit Canton',
    keywords: ['lucky me', 'pancit canton'],
  ),
  _SampleProduct(
    category: 'food',
    product: 'Oreo Cookies',
    keywords: ['oreo', 'cookie'],
  ),
  _SampleProduct(
    category: 'food',
    product: 'Milo Powder Drink',
    keywords: ['milo', 'powder'],
  ),
  _SampleProduct(
    category: 'supplement',
    product: 'Myra E',
    keywords: ['myra e', 'tocopheryl'],
  ),
  _SampleProduct(
    category: 'supplement',
    product: 'Enervon',
    keywords: ['enervon'],
  ),
  _SampleProduct(
    category: 'supplement',
    product: 'Centrum Advance',
    keywords: ['centrum'],
  ),
  _SampleProduct(
    category: 'supplement',
    product: 'Fern-C',
    keywords: ['fern-c', 'ascorbic'],
  ),
  _SampleProduct(
    category: 'supplement',
    product: 'Potencee',
    keywords: ['potencee'],
  ),
  _SampleProduct(
    category: 'cosmetic',
    product: "Pond's Facial Wash",
    keywords: ['ponds', 'facial wash'],
  ),
  _SampleProduct(
    category: 'cosmetic',
    product: 'Olay Skin Cream',
    keywords: ['olay', 'skin cream'],
  ),
  _SampleProduct(
    category: 'cosmetic',
    product: 'Nivea Sun Protect',
    keywords: ['nivea', 'sunblock', 'sun protect'],
  ),
  _SampleProduct(
    category: 'cosmetic',
    product: 'Belo Kojic Soap',
    keywords: ['belo', 'kojic'],
  ),
  _SampleProduct(
    category: 'cosmetic',
    product: 'Celeteque Hydration',
    keywords: ['celeteque', 'hydration'],
  ),
];
