import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Attempts to initialize Firebase. If not configured yet, it safely
/// swallows errors so the app keeps working offline.
///
/// Note: When you run `flutterfire configure`, you can import the generated
/// `firebase_options.dart` and call `Firebase.initializeApp(options: ...)`.
Future<void> tryInitFirebase() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FirebaseBootstrap] Firebase not initialized: $e');
    }
  }
}

