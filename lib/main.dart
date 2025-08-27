import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'services/fda_checker.dart';
import 'screens/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Load camera list
  final cameras = await availableCameras();

  // ✅ Initialize FDA Checker and load CSV
  final fdaChecker = FDAChecker();
  await fdaChecker.loadCSV();

  runApp(BastaFDAApp(cameras: cameras, fdaChecker: fdaChecker));
}

class BastaFDAApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;

  const BastaFDAApp({super.key, required this.cameras, required this.fdaChecker});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'bastaFDA',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ScannerScreen(cameras: cameras, fdaChecker: fdaChecker),
    );
  }
}
