// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basta_fda/screens/scanner_screen.dart';
import 'package:basta_fda/services/fda_checker.dart';

void main() {
  testWidgets('ScannerScreen loads Scan button', (WidgetTester tester) async {
    final fdaChecker = FDAChecker();

    await tester.pumpWidget(MaterialApp(
      home: ScannerScreen(
        cameras: [], // Empty for testing
        fdaChecker: fdaChecker,
      ),
    ));

    // Verify that Scan Product button exists
    expect(find.text('Scan Product'), findsOneWidget);
  });
}

