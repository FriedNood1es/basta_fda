class PackagingTrainedProduct {
  final String category;
  final String name;
  final List<String> keywords;

  const PackagingTrainedProduct({
    required this.category,
    required this.name,
    required this.keywords,
  });

  bool matchesNormalizedText(String normalized) {
    return keywords.any(normalized.contains);
  }

  bool matchesName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final normalized = PackagingCoverage.normalize(raw);
    if (normalized.isEmpty) return false;
    final nameToken = PackagingCoverage.normalize(name);
    if (normalized.contains(nameToken) || nameToken.contains(normalized)) {
      return true;
    }
    return keywords.any(normalized.contains);
  }
}

class PackagingCoverage {
  static const List<PackagingTrainedProduct> products = [
    PackagingTrainedProduct(
      category: 'Medicine',
      name: 'Biogesic',
      keywords: ['biogesic', 'paracetamol'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine',
      name: 'Bioflu',
      keywords: ['bioflu', 'phenylephrine'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine',
      name: 'Alaxan',
      keywords: ['alaxan', 'ibuprofen'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine',
      name: 'Neozep',
      keywords: ['neozep', 'phenylpropanolamine'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine',
      name: 'Ascof Lagundi',
      keywords: ['lagundi', 'ascof'],
    ),
    PackagingTrainedProduct(
      category: 'Food',
      name: 'SkyFlakes Crackers',
      keywords: ['skyflakes', 'cracker'],
    ),
    PackagingTrainedProduct(
      category: 'Food',
      name: 'Bear Brand Milk',
      keywords: ['bear brand', 'milk'],
    ),
    PackagingTrainedProduct(
      category: 'Food',
      name: 'Lucky Me Pancit Canton',
      keywords: ['lucky me', 'pancit canton'],
    ),
    PackagingTrainedProduct(
      category: 'Food',
      name: 'Oreo Cookies',
      keywords: ['oreo', 'cookie'],
    ),
    PackagingTrainedProduct(
      category: 'Food',
      name: 'Milo Powder Drink',
      keywords: ['milo', 'powder'],
    ),
    PackagingTrainedProduct(
      category: 'Supplement',
      name: 'Myra E',
      keywords: ['myra e', 'tocopheryl'],
    ),
    PackagingTrainedProduct(
      category: 'Supplement',
      name: 'Enervon',
      keywords: ['enervon'],
    ),
    PackagingTrainedProduct(
      category: 'Supplement',
      name: 'Centrum Advance',
      keywords: ['centrum'],
    ),
    PackagingTrainedProduct(
      category: 'Supplement',
      name: 'Fern-C',
      keywords: ['fern-c', 'ascorbic'],
    ),
    PackagingTrainedProduct(
      category: 'Supplement',
      name: 'Potencee',
      keywords: ['potencee'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetic',
      name: "Pond's Facial Wash",
      keywords: ['ponds', 'facial wash'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetic',
      name: 'Olay Skin Cream',
      keywords: ['olay', 'skin cream'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetic',
      name: 'Nivea Sun Protect',
      keywords: ['nivea', 'sunblock', 'sun protect'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetic',
      name: 'Belo Kojic Soap',
      keywords: ['belo', 'kojic'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetic',
      name: 'Celeteque Hydration',
      keywords: ['celeteque', 'hydration'],
    ),
  ];

  static List<String> previewNames([int limit = 3]) {
    return products.take(limit).map((p) => p.name).toList();
  }

  static Map<String, List<PackagingTrainedProduct>> byCategory() {
    final map = <String, List<PackagingTrainedProduct>>{};
    for (final product in products) {
      map.putIfAbsent(product.category, () => []).add(product);
    }
    return map;
  }

  static bool matchesProduct(Map<String, String>? productInfo) {
    if (productInfo == null) return false;
    return matchesName(productInfo['brand_name']) ||
        matchesName(productInfo['generic_name']);
  }

  static bool matchesName(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return products.any((p) => p.matchesName(value));
  }

  static bool matchesNormalizedText(String normalizedText) {
    if (normalizedText.isEmpty) return false;
    return products.any((p) => p.matchesNormalizedText(normalizedText));
  }

  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

