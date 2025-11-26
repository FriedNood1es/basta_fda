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
    // Supplements - Vitamins & Antioxidants
    PackagingTrainedProduct(
      category: 'Supplements · Vitamins & Antioxidants',
      name: 'MX3',
      keywords: ['mx3'],
    ),
    PackagingTrainedProduct(
      category: 'Supplements · Vitamins & Antioxidants',
      name: 'Myra-E',
      keywords: ['myra e', 'myra-e', 'tocopheryl'],
    ),
    PackagingTrainedProduct(
      category: 'Supplements · Vitamins & Antioxidants',
      name: 'Enervon',
      keywords: ['enervon'],
    ),
    // Supplements - Liver & Blood Health
    PackagingTrainedProduct(
      category: 'Supplements · Liver & Blood Health',
      name: 'Liveraide',
      keywords: ['liveraide'],
    ),
    // Food Products - 555 series
    PackagingTrainedProduct(
      category: 'Food · 555 Tuna Series',
      name: '555 Tuna Afritada',
      keywords: ['555 tuna', 'afritada'],
    ),
    PackagingTrainedProduct(
      category: 'Food · 555 Tuna Series',
      name: '555 Tuna Mechado',
      keywords: ['555 tuna', 'mechado'],
    ),
    PackagingTrainedProduct(
      category: 'Food · 555 Sardines Series',
      name: '555 Sardines',
      keywords: ['555 sardines'],
    ),
    PackagingTrainedProduct(
      category: 'Food · 555 Sardines Series',
      name: '555 Sardines (Spicy)',
      keywords: ['555 sardines', 'spicy'],
    ),
    // Food Products - Mega Sardines series
    PackagingTrainedProduct(
      category: 'Food · Mega Sardines Series',
      name: 'Mega Sardines (Green)',
      keywords: ['mega sardines', 'green'],
    ),
    PackagingTrainedProduct(
      category: 'Food · Mega Sardines Series',
      name: 'Mega Sardines (Red)',
      keywords: ['mega sardines', 'red'],
    ),
    // Other common food brands
    PackagingTrainedProduct(
      category: 'Food · Corned Beef',
      name: 'Argentina Corned Beef',
      keywords: ['argentina corned beef', 'argentina corned'],
    ),
    PackagingTrainedProduct(
      category: 'Food · Corned Beef',
      name: 'Holiday Corned Beef',
      keywords: ['holiday corned beef', 'holiday corned'],
    ),
    PackagingTrainedProduct(
      category: 'Food · Noodles',
      name: 'Lucky Me! Noodles',
      keywords: ['lucky me', 'noodles'],
    ),
    // Cosmetics / Personal Care
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Ashley',
      keywords: ['ashley'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Careline',
      keywords: ['careline'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'DW',
      keywords: ['dw'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Fairy Skin',
      keywords: ['fairy skin'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Hally',
      keywords: ['hally'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Human Nature',
      keywords: ['human nature'],
    ),
    PackagingTrainedProduct(
      category: 'Cosmetics / Personal Care',
      name: 'Kiko Milano',
      keywords: ['kiko milano', 'kiko'],
    ),
    // Medicines - Paracetamol
    PackagingTrainedProduct(
      category: 'Medicine · Paracetamol',
      name: 'Biogesic',
      keywords: ['biogesic', 'paracetamol'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Paracetamol',
      name: 'Saridon',
      keywords: ['saridon'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Paracetamol',
      name: 'TGP Paracetamol',
      keywords: ['tgp', 'paracetamol'],
    ),
    // Medicines - Combo cold/flu with paracetamol
    PackagingTrainedProduct(
      category: 'Medicine · Cold/Flu Combo',
      name: 'Bioflu',
      keywords: ['bioflu'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Cold/Flu Combo',
      name: 'Neozep Z+',
      keywords: ['neozep', 'z+', 'phenylephrine'],
    ),
    // Medicines - Ibuprofen
    PackagingTrainedProduct(
      category: 'Medicine · Ibuprofen',
      name: 'Advil',
      keywords: ['advil', 'ibuprofen'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Ibuprofen',
      name: 'Fevral',
      keywords: ['fevral'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Ibuprofen',
      name: 'Medicol Advance',
      keywords: ['medicol', 'ibuprofen'],
    ),
    // Medicines - Loperamide
    PackagingTrainedProduct(
      category: 'Medicine · Loperamide',
      name: 'Loniper',
      keywords: ['loniper', 'loperamide'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Loperamide',
      name: 'Diatabs',
      keywords: ['diatabs', 'loperamide'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Loperamide',
      name: 'Imodium',
      keywords: ['imodium', 'loperamide'],
    ),
    // Medicines - Antihistamines
    PackagingTrainedProduct(
      category: 'Medicine · Antihistamine',
      name: 'Loratadine',
      keywords: ['loratadine'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Antihistamine',
      name: 'Claritin',
      keywords: ['claritin', 'loratadine'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Antihistamine',
      name: 'Cetirizine',
      keywords: ['cetirizine'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Antihistamine',
      name: 'RiteMED Cetirizine',
      keywords: ['ritemed cetirizine', 'ritemed'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Antihistamine',
      name: 'Ceticit Cetirizine',
      keywords: ['ceticit', 'cetirizine'],
    ),
    // Medicines - Cough / Cold preparations
    PackagingTrainedProduct(
      category: 'Medicine · Cough/Cold',
      name: 'Robitussin (Dextromethorphan + Guaifenesin)',
      keywords: ['robitussin', 'dextromethorphan', 'guaifenesin'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Cough/Cold',
      name: 'Tuseran Night',
      keywords: ['tuseran night', 'tuseran'],
    ),
    PackagingTrainedProduct(
      category: 'Medicine · Cough/Cold',
      name: 'Vicks Formula 44',
      keywords: ['vicks formula 44', 'formula 44', 'vicks 44'],
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
