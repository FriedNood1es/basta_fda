import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Helper that updates the cached FDA CSV from Firebase using a simple
/// manifest document and a Storage object. All failures are swallowed and
/// reported via `false` to avoid breaking offline flows.
///
/// Expected Firestore doc: collection `meta`, doc `fda_manifest` with fields:
/// - `csvPath`: string, e.g. `datasets/ALL_DrugProducts.csv`
/// - `version`: string (optional)
/// - `updatedAt`: timestamp (optional)
///
/// Storage object: at `csvPath` containing the CSV bytes.
class FdaFirebaseUpdater {
  FdaFirebaseUpdater({required this.cacheFileName});

  final String cacheFileName;

  Future<bool> updateFromManifest() async {
    try {
      // Initialize Firebase if needed; this will succeed only if the host app
      // is properly configured (google-services.json / GoogleService-Info.plist
      // or web options). Any failure will be caught below.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final doc = await FirebaseFirestore.instance
          .collection('meta')
          .doc('fda_manifest')
          .get();
      if (!doc.exists) return false;
      final data = doc.data() ?? {};
      final path = (data['csvPath'] as String?)?.trim();
      if (path == null || path.isEmpty) return false;

      final ref = FirebaseStorage.instance.ref(path);
      // Download as bytes (max ~50MB default is safe for typical CSVs).
      final bytes = await ref.getData();
      if (bytes == null || bytes.isEmpty) return false;

      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/$cacheFileName');
      await out.writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // Log in debug builds; keep silent in release.
        // ignore: avoid_print
        print('[FdaFirebaseUpdater] update failed: $e');
      }
      return false;
    }
  }
}

