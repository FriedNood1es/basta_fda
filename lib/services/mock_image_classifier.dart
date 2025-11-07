class ImagePrediction {
  final String category;
  final String productName;
  final double confidence;
  final String source;

  const ImagePrediction({
    required this.category,
    required this.productName,
    required this.confidence,
    this.source = 'mock-dataset',
  });

  Map<String, String> toMap() => {
        'category': category,
        'product': productName,
        'confidence': confidence.toStringAsFixed(2),
        'source': source,
      };
}

class MockImageClassifier {
  MockImageClassifier._();
  static final MockImageClassifier instance = MockImageClassifier._();

  static final List<_SampleProduct> _samples = [
    // Medicine samples
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

    // Food products
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

    // Supplements
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

    // Cosmetics
    _SampleProduct(
      category: 'cosmetic',
      product: 'Pond\'s Facial Wash',
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

  Future<ImagePrediction?> classify({
    required String rawText,
    String? additionalText,
  }) async {
    final combined = StringBuffer()
      ..write(rawText.toLowerCase());
    if ((additionalText ?? '').isNotEmpty) {
      combined.write(' ');
      combined.write(additionalText!.toLowerCase());
    }
    final normalized = combined.toString();
    for (final sample in _samples) {
      if (sample.matches(normalized)) {
        return ImagePrediction(
          category: sample.category,
          productName: sample.product,
          confidence: sample.confidence,
          source: 'mock-sample',
        );
      }
    }
    // Simple heuristics while dataset is incomplete
    if (normalized.contains('tablet') || normalized.contains('capsule')) {
      return ImagePrediction(
        category: 'medicine',
        productName: 'Unrecognized tablet',
        confidence: 0.55,
        source: 'heuristic',
      );
    }
    if (normalized.contains('vitamin') || normalized.contains('supplement')) {
      return ImagePrediction(
        category: 'supplement',
        productName: 'Unrecognized supplement',
        confidence: 0.6,
        source: 'heuristic',
      );
    }
    if (normalized.contains('cream') ||
        normalized.contains('lotion') ||
        normalized.contains('facial')) {
      return ImagePrediction(
        category: 'cosmetic',
        productName: 'Unrecognized cosmetic',
        confidence: 0.58,
        source: 'heuristic',
      );
    }
    if (normalized.contains('drink') ||
        normalized.contains('snack') ||
        normalized.contains('chocolate')) {
      return ImagePrediction(
        category: 'food',
        productName: 'Unrecognized food item',
        confidence: 0.52,
        source: 'heuristic',
      );
    }
    return null;
  }
}

class _SampleProduct {
  final String category;
  final String product;
  final List<String> keywords;
  final double confidence;

  _SampleProduct({
    required this.category,
    required this.product,
    required this.keywords,
    this.confidence = 0.92,
  });

  bool matches(String text) {
    return keywords.any((kw) => text.contains(kw));
  }
}
