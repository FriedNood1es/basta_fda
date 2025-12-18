import 'package:flutter_test/flutter_test.dart';
import 'package:basta_fda/services/image_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('debug packaging asset classification logs results', () async {
    final classifier = PackagingImageClassifier.instance;
    await classifier.logDebugAssetClassification(
      assetPath: 'assets/debug/555_tuna_spicy_auth_23.jpg',
    );
  });
}
