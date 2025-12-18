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
  // Skip: ScannerScreen requires real cameras; omit in headless test env.
  testWidgets('ScannerScreen renders without camera when disabled',
      (WidgetTester tester) async {
    final fdaChecker = FDAChecker();

    await tester.pumpWidget(MaterialApp(
      home: ScannerScreen(
        cameras: const [],
        fdaChecker: fdaChecker,
        cameraEnabled: false,
      ),
    ));

    expect(find.text('Scan Product'), findsOneWidget);
    expect(find.text('Camera disabled in test mode'), findsOneWidget);
  });
}

