import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum PackagingModelCategory { food, cosmetics, supplements, medicine }

class PackagingModelConfig {
  final String modelAsset;
  final String labelAsset;

  const PackagingModelConfig({
    required this.modelAsset,
    required this.labelAsset,
  });
}

const Map<PackagingModelCategory, PackagingModelConfig> _modelConfigs = {
  PackagingModelCategory.food: PackagingModelConfig(
    modelAsset: 'assets/models/food_model.tflite',
    labelAsset: 'assets/food_labels.txt',
  ),
  PackagingModelCategory.cosmetics: PackagingModelConfig(
    modelAsset: 'assets/models/cosmetics_model.tflite',
    labelAsset: 'assets/cosmetics_labels.txt',
  ),
  PackagingModelCategory.supplements: PackagingModelConfig(
    modelAsset: 'assets/models/supplements_model.tflite',
    labelAsset: 'assets/supplements_labels.txt',
  ),
  PackagingModelCategory.medicine: PackagingModelConfig(
    modelAsset: 'assets/models/medicine_model.tflite',
    labelAsset: 'assets/medicine_labels.txt',
  ),
};

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
  PackagingModelCategory _currentCategory = PackagingModelCategory.food;
  int _outputClassCount = 0;
  int _inputHeight = 224;
  int _inputWidth = 224;
  int _inputChannels = 3;
  Future<void>? _loading;

  static const int _maxFrameBatch = 5;
  static const double _absoluteMinConfidence = 0.15;

  double _suspiciousThreshold = 0.5;
  double _temperature = 1.0;

  Future<void> _ensureLoaded(PackagingModelCategory category) async {
    if (_interpreter != null &&
        _labels != null &&
        _currentCategory == category) {
      return;
    }
    _loading ??= _loadResources(category);
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadResources(PackagingModelCategory category) async {
    try {
      _currentCategory = category;
      final config =
          _modelConfigs[category] ??
          _modelConfigs[PackagingModelCategory.food]!;
      Interpreter? interpreter;
      try {
        interpreter = await Interpreter.fromAsset(config.modelAsset);
        debugPrint('Loaded packaging model: ${config.modelAsset}');
      } catch (e, stack) {
        debugPrint('Failed to load packaging model ${config.modelAsset}: $e');
        debugPrint('$stack');
        rethrow;
      }
      _interpreter = interpreter;
      _loadedModelAsset = config.modelAsset;
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
      String? labelText;
      try {
        labelText = await rootBundle.loadString(config.labelAsset);
        debugPrint('Loaded packaging labels: ${config.labelAsset}');
      } catch (e) {
        throw Exception('Unable to load label file ${config.labelAsset}: $e');
      }
      _labels = labelText
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

  void updateConfidenceConfig({
    double? suspiciousThreshold,
    double? temperature,
  }) {
    if (suspiciousThreshold != null) {
      _suspiciousThreshold = suspiciousThreshold.clamp(0.1, 0.95);
    }
    if (temperature != null && temperature > 0) {
      _temperature = temperature;
    }
  }

  Future<ImagePrediction?> classify({
    required String rawText,
    String? additionalText,
    String? imagePath,
    PackagingModelCategory category = PackagingModelCategory.food,
    List<String>? framePaths,
  }) async {
    await _ensureLoaded(category);

    if (_loadedModelAsset != null && imagePath != null) {
      debugPrint('Packaging scan using model: $_loadedModelAsset');
    }

    final frames = _prepareFrameBatch(imagePath, framePaths);

    if (_interpreter == null || frames.isEmpty) {
      return null;
    }

    final classCount = _outputClassCount > 0
        ? _outputClassCount
        : (_labels?.length ?? 0);
    if (classCount <= 0) {
      return null;
    }

    try {
      final aggregated = List<double>.filled(classCount, 0);
      var processedFrames = 0;

      for (var i = 0; i < frames.length; i++) {
        final probs = await _runFrame(frames[i], classCount, i + 1);
        if (probs == null || probs.isEmpty) continue;
        final limit = math.min(classCount, probs.length);
        for (var j = 0; j < limit; j++) {
          aggregated[j] += probs[j];
        }
        processedFrames++;
      }

      if (processedFrames == 0) {
        debugPrint('Packaging helper: no usable frames for classification.');
        return null;
      }

      final averaged = aggregated
          .map((score) => score / processedFrames)
          .toList();
      debugPrint(
        'Packaging avg probs ($processedFrames frames): ${averaged.toString()}',
      );

      final bestIndex = _argMax(averaged);
      if (bestIndex < 0) {
        return null;
      }
      final confidence = averaged[bestIndex];
      if (confidence.isNaN || confidence < _absoluteMinConfidence) {
        debugPrint('Packaging helper: confidence below absolute minimum');
        return null;
      }

      final labelInfo = _labelInfoForIndex(bestIndex);
      final authenticity = confidence.clamp(0.0, 1.0).toDouble();
      final suspicious = (1 - authenticity).clamp(0.0, 1.0).toDouble();
      final productName = labelInfo.category;
      final verdictValue = authenticity >= _suspiciousThreshold
          ? 'authentic'
          : 'suspicious';
      final categoryLabel = _modelCategoryLabel(category);

      debugPrint(
        'Packaging final => $productName | confidence ${(authenticity * 100).toStringAsFixed(1)}% (threshold ${(_suspiciousThreshold * 100).toStringAsFixed(0)}%)',
      );

      return ImagePrediction(
        category: categoryLabel,
        productName: productName,
        confidence: authenticity,
        source: 'tflite',
        verdict: verdictValue,
        authenticScore: authenticity,
        suspiciousScore: suspicious,
      );
    } catch (e, stack) {
      debugPrint('Image classification error: $e');
      debugPrint('$stack');
      return null;
    }
  }

  List<List<List<Float32List>>> _convertToInput(img.Image image) {
    final resized = img.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );
    final channels = _inputChannels.clamp(1, 4).toInt();
    return [
      List.generate(
        _inputHeight,
        (y) => List.generate(_inputWidth, (x) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          if (channels <= 1) {
            final gray = (r + g + b) / 3;
            final buffer = Float32List(1);
            buffer[0] = gray;
            return buffer;
          }
          final buffer = Float32List(channels);
          final values = [r, g, b, pixel.a.toDouble()];
          for (var i = 0; i < channels; i++) {
            buffer[i] = i < values.length ? values[i] : 0;
          }
          return buffer;
        }),
      ),
    ];
  }

  List<String> _prepareFrameBatch(String? fallback, List<String>? framePaths) {
    final result = <String>[];
    final seen = <String>{};
    void addPath(String? path) {
      if (path == null || path.isEmpty || seen.length >= _maxFrameBatch) {
        return;
      }
      if (seen.add(path)) {
        result.add(path);
      }
    }

    if (framePaths != null && framePaths.isNotEmpty) {
      for (final path in framePaths) {
        addPath(path);
      }
    } else {
      addPath(fallback);
    }
    return result;
  }

  Future<List<double>?> _runFrame(
    String path,
    int classCount,
    int frameIndex,
  ) async {
    final file = File(path);
    if (!await file.exists()) {
      debugPrint('Packaging frame $frameIndex missing at $path');
      return null;
    }
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      debugPrint('Packaging frame $frameIndex decode failed');
      return null;
    }
    final input = _convertToInput(decoded);
    final output = List.generate(1, (_) => List<double>.filled(classCount, 0));
    _interpreter!.run(input, output);
    final raw = output.first;
    debugPrint('Packaging raw[f$frameIndex]: $raw');
    final probs = _calibrateProbabilities(raw);
    debugPrint('Packaging probs[f$frameIndex]: $probs');
    return probs;
  }

  List<double> _calibrateProbabilities(List<double> raw) {
    if (raw.isEmpty) return raw;
    final sum = raw.fold(0.0, (a, b) => a + b);
    final bool looksNormalized =
        raw.every(
          (value) => value.isFinite && value >= 0.0 && value <= 1.0001,
        ) &&
        (sum - 1.0).abs() <= 0.05;
    final base = looksNormalized ? List<double>.from(raw) : _softmax(raw);
    return _applyTemperature(base);
  }

  List<double> _applyTemperature(List<double> probs) {
    final temp = _temperature <= 0 ? 1.0 : _temperature;
    if ((temp - 1.0).abs() < 0.0001) {
      return List<double>.from(probs);
    }
    final adjusted = probs.map((value) {
      final safe = value.clamp(1e-9, 1.0).toDouble();
      return math.pow(safe, 1 / temp).toDouble();
    }).toList();
    final sum = adjusted.fold(0.0, (a, b) => a + b);
    if (sum == 0) {
      return probs;
    }
    return adjusted.map((value) => value / sum).toList();
  }

  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return logits;
    final temp = _temperature <= 0 ? 1.0 : _temperature;
    final scaled = logits.map((value) => value / temp).toList();
    final maxLogit = scaled.reduce(math.max);
    var sum = 0.0;
    final expValues = List<double>.filled(scaled.length, 0);
    for (var i = 0; i < scaled.length; i++) {
      final value = math.exp(scaled[i] - maxLogit);
      expValues[i] = value;
      sum += value;
    }
    if (sum == 0) {
      return logits;
    }
    return expValues.map((value) => value / sum).toList();
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

  String _modelCategoryLabel(PackagingModelCategory category) {
    switch (category) {
      case PackagingModelCategory.food:
        return 'Food';
      case PackagingModelCategory.cosmetics:
        return 'Cosmetics';
      case PackagingModelCategory.supplements:
        return 'Supplements';
      case PackagingModelCategory.medicine:
        return 'Medicine';
    }
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

  Future<void> logDebugAssetClassification({
    required String assetPath,
    PackagingModelCategory category = PackagingModelCategory.food,
  }) async {
    assert(() {
      debugPrint('--- Debug classification for $assetPath ---');
      return true;
    }());
    final data = await rootBundle.load(assetPath);
    final decoded = img.decodeImage(data.buffer.asUint8List());
    if (decoded == null) {
      debugPrint('Debug asset decode failed for $assetPath');
      return;
    }
    await _ensureLoaded(category);
    if (_interpreter == null) {
      debugPrint('Interpreter not initialized for $assetPath');
      return;
    }
    final input = _convertToInput(decoded);
    final stats = _tensorStats(input);
    debugPrint(
      'Input stats => min:${stats.min.toStringAsFixed(4)} '
      'max:${stats.max.toStringAsFixed(4)} '
      'avg:${stats.mean.toStringAsFixed(4)}',
    );
    final classCount = _outputClassCount > 0
        ? _outputClassCount
        : (_labels?.length ?? 0);
    if (classCount <= 0) {
      debugPrint('Interpreter missing output shape information.');
      return;
    }
    final output = List.generate(1, (_) => List<double>.filled(classCount, 0));
    _interpreter!.run(input, output);
    final probs = _calibrateProbabilities(output.first);
    final labels =
        _labels ?? List.generate(classCount, (i) => 'Class ${i + 1}');
    debugPrint('--- Label order ---');
    for (var i = 0; i < labels.length && i < probs.length; i++) {
      debugPrint('[$i] ${labels[i]} => ${probs[i].toStringAsFixed(4)}');
    }
    final best = _argMax(probs);
    if (best >= 0 && best < labels.length) {
      debugPrint(
        'Top class: ${labels[best]} (confidence ${(probs[best] * 100).toStringAsFixed(2)}%)',
      );
    }
  }

  _TensorStats _tensorStats(List<List<List<Float32List>>> tensor) {
    double min = double.infinity;
    double max = double.negativeInfinity;
    double sum = 0;
    int count = 0;
    for (final rows in tensor) {
      for (final row in rows) {
        for (final values in row) {
          for (final value in values) {
            if (value < min) min = value;
            if (value > max) max = value;
            sum += value;
            count++;
          }
        }
      }
    }
    final double mean = count == 0 ? 0.0 : sum / count;
    return _TensorStats(min, max, mean);
  }
}

class _TensorStats {
  final double min;
  final double max;
  final double mean;

  const _TensorStats(this.min, this.max, this.mean);
}

class _LabelInfo {
  final String category;
  final String status;

  const _LabelInfo({required this.category, required this.status});

  bool get isSuspicious => status.contains('suspicious');
}
