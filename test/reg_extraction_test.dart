import 'package:flutter_test/flutter_test.dart';
import 'package:basta_fda/services/fda_checker.dart';

void main() {
  group('Registration extraction', () {
    final checker = FDAChecker();
    String normalize(String input) =>
        input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    test('captures multi-segment code with dash', () {
      final text = 'Registration Number: DR-XY46593';
      final candidates = checker.regCandidates(text);
      final normalized = candidates.map(normalize).toSet();
      expect(normalized.contains('drxy46593'), isTrue);
    });

    test('captures multi-segment code with space', () {
      final text = 'reg no. dr xy46593 printed on label';
      final candidates = checker.regCandidates(text);
      final normalized = candidates.map(normalize).toSet();
      expect(normalized.contains('drxy46593'), isTrue);
    });

    test('keeps full leading segment when mixed text surrounds it', () {
      final text = 'Info: DR-XY46593 PIL 01 pdf Reg. Number';
      final candidates = checker.regCandidates(text);
      expect(candidates.isNotEmpty, isTrue);
      expect(
        candidates.any((c) => normalize(c) == 'drxy46593'),
        isTrue,
      );
    });

    test('captures codes even with spaces around dashes', () {
      final text = 'FDA Reg. No.: DRP-681 - 02 keep entire code';
      final candidates = checker.regCandidates(text);
      expect(
        candidates.any((c) => normalize(c) == 'drp68102'),
        isTrue,
      );
      expect(
        normalize(checker.extractRegNumber('reg no DRP-681 - 02') ?? ''),
        equals('drp68102'),
      );
    });

    test('_extractRegNumber handles spaces/dashes consistently', () {
      expect(
        checker.extractRegNumber('reg no. dr xy46593'),
        equals('DR XY46593'),
      );
      expect(
        checker.extractRegNumber('reg no: DR-XY46593'),
        equals('DR-XY46593'),
      );
      expect(
        checker.extractRegNumber('random text'),
        isNull,
      );
    });
  });
}
