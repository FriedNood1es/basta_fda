import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';
import 'package:basta_fda/screens/not_found_screen.dart';

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;

  const ScannerScreen({super.key, required this.cameras, required this.fdaChecker});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isScanning = false;
  String _extractedText = "";

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(widget.cameras.first, ResolutionPreset.medium);
    await _controller!.initialize();
    setState(() => _isInitialized = true);
  }

  Future<void> _captureAndScan() async {
    if (!_controller!.value.isInitialized) return;

    setState(() {
      _isScanning = true;
      _extractedText = "Scanning...";
    });

    final XFile file = await _controller!.takePicture();
    final inputImage = InputImage.fromFilePath(file.path);
    final textRecognizer = TextRecognizer();
    final RecognizedText result = await textRecognizer.processImage(inputImage);
    final scannedText = cleanText(result.text);

    setState(() {
      _extractedText = scannedText;
      _isScanning = false;
    });
  }

  Future<void> _matchScannedText() async {
    final matchedProduct = widget.fdaChecker.findProductDetails(_extractedText);

    if (!mounted) return;

    if (matchedProduct != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanResultScreen(
            productInfo: matchedProduct,
            status: 'VERIFIED', // Later we can make this dynamic (Expired, Not Found)
          ),
        ),
      );
      
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NotFoundScreen(scannedText: _extractedText)),
      );
    }
  }

  String cleanText(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Product')),
      body: Column(
        children: [
          AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CameraPreview(_controller!)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isScanning ? null : _captureAndScan,
            child: _isScanning ? const CircularProgressIndicator() : const Text("Scan Now"),
          ),
          if (_extractedText.isNotEmpty && !_isScanning) ...[
            const SizedBox(height: 20),
            const Text("Extracted Text:"),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_extractedText),
            ),
            ElevatedButton(onPressed: _matchScannedText, child: const Text("Confirm Scan")),
          ]
        ],
      ),
    );
  }
}
