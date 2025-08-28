import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
  bool _streaming = false;
  bool _isBusy = false;
  bool _paused = false;
  bool _torchOn = false;
  bool _liveMode = false; // Lens-like live OCR (off by default)
  String _extractedText = "";
  List<String> _suggestions = [];
  Size? _imageSize;
  final TextRecognizer _textRecognizer = TextRecognizer();
  Timer? _debounce;
  bool _isCapturing = false;
  bool _showExtractedExpanded = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    setState(() => _isInitialized = true);
    // Do not start stream by default to avoid ImageReader buffer pressure.
  }

  Future<void> _startStream() async {
    if (!mounted || _controller == null || _controller!.value.isStreamingImages) return;
    _streaming = true;
    await _controller!.startImageStream(_onImage);
  }

  Future<void> _stopStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    _streaming = false;
  }

  Future<void> _onImage(CameraImage cameraImage) async {
    if (_paused || !_liveMode || _isBusy) return;
    if (_debounce?.isActive ?? false) return;
    _debounce = Timer(const Duration(milliseconds: 350), () {});
    _isBusy = true;

    _imageSize ??= Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotationValue.fromRawValue(_controller!.description.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw) ?? InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
          rotation: imageRotation,
          format: format,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );

      final RecognizedText result = await _textRecognizer.processImage(inputImage);
      final rawText = result.text;
      final scannedText = cleanText(rawText);

      // Keep logs minimal in live mode to reduce overhead

      final suggestions = _extractSuggestions(result);

      if (!mounted) return;
      setState(() {
        _extractedText = scannedText;
        _suggestions = suggestions;
      });
    } catch (_) {
      // ignore
    } finally {
      _isBusy = false;
    }
  }

  // Reliable still-shot scan used for Confirm action
  Future<String?> _scanFromPhoto() async {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return null;
    try {
      setState(() => _isCapturing = true);
      // Stop the stream before capture to avoid conflicts
      await _stopStream();

      final XFile file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);
      final rawText = result.text;
      final scannedText = cleanText(rawText);

      debugPrint('----- OCR RAW TEXT START -----');
      debugPrint(rawText);
      debugPrint('----- OCR RAW TEXT END -----');
      debugPrint('----- OCR CLEANED TEXT START -----');
      debugPrint(scannedText);
      debugPrint('----- OCR CLEANED TEXT END -----');

      if (!mounted) return scannedText;
      setState(() {
        _extractedText = scannedText;
      });
      return scannedText;
    } catch (e) {
      debugPrint('OCR photo scan error: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
        // Resume stream for live UI only if live mode is enabled
        if (_liveMode) {
          await _startStream();
        }
      }
    }
  }

  List<String> _extractSuggestions(RecognizedText result) {
    final List<String> collect = [];
    final imgW = _imageSize?.width ?? 1;
    final imgH = _imageSize?.height ?? 1;
    final roi = Rect.fromLTWH(imgW * 0.2, imgH * 0.325, imgW * 0.6, imgH * 0.35);
    for (final block in result.blocks) {
      final box = block.boundingBox;
      if (box == null) continue;
      if (roi.overlaps(box)) {
        final text = cleanText(block.text);
        for (final t in text.split(' ')) {
          if (t.length >= 4 && !collect.contains(t)) collect.add(t);
        }
      }
    }
    collect.sort((a, b) => b.length.compareTo(a.length));
    return collect.take(8).toList();
  }

  Future<void> _matchScannedText() async {
    // Review step before searching so users can see/edit the text first
    await _reviewAndSearch();
  }

  Future<void> _reviewAndSearch() async {
    // Capture a fresh still for reliable OCR
    final text = await _scanFromPhoto();
    if (!mounted) return;
    String working = text ?? _extractedText;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final controller = TextEditingController(text: working);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Review Extracted Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: controller.text));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                      }
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: 'Edit or confirm the extracted text',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => working = v,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _executeSearch(working);
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Use & Search'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _executeSearch(String text) async {
    final matchedProduct = widget.fdaChecker.findProductDetails(text);
    if (!mounted) return;
    if (matchedProduct != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanResultScreen(
            productInfo: matchedProduct,
            status: 'VERIFIED',
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NotFoundScreen(scannedText: text)),
      );
    }
  }

  String cleanText(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void dispose() {
    _stopStream();
    _textRecognizer.close();
    _debounce?.cancel();
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
      body: Stack(
        children: [
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ReticlePainter(color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                _roundIconButton(
                  icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  tooltip: _paused ? 'Resume' : 'Pause',
                  onTap: () => setState(() => _paused = !_paused),
                ),
                const SizedBox(height: 10),
                _roundIconButton(
                  icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  tooltip: _torchOn ? 'Torch On' : 'Torch Off',
                  onTap: () async {
                    try {
                      _torchOn = !_torchOn;
                      await _controller!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
                      setState(() {});
                    } catch (_) {}
                  },
                ),
                const SizedBox(height: 10),
                _roundIconButton(
                  icon: _liveMode ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  tooltip: _liveMode ? 'Live OCR On' : 'Live OCR Off',
                  onTap: () async {
                    setState(() => _liveMode = !_liveMode);
                    if (_liveMode) {
                      await _startStream();
                    } else {
                      await _stopStream();
                    }
                  },
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
          child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Extracted text viewer (cleaned), with copy and expand controls
                  if (_extractedText.isNotEmpty) ...[
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Extracted Text', style: TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  tooltip: 'Copy',
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: _extractedText));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Extracted text copied')));
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(_showExtractedExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                                  tooltip: _showExtractedExpanded ? 'Collapse' : 'Expand',
                                  onPressed: () => setState(() => _showExtractedExpanded = !_showExtractedExpanded),
                                ),
                              ],
                            ),
                            AnimatedCrossFade(
                              crossFadeState: _showExtractedExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 180),
                              firstChild: Text(
                                _extractedText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black87),
                              ),
                              secondChild: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: Text(_extractedText, style: const TextStyle(color: Colors.black87)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: -6,
                    children: _suggestions.take(6).map((t) {
                      return ChoiceChip(
                        label: Text(t, style: const TextStyle(color: Colors.white)),
                        selected: _extractedText.contains(t),
                        selectedColor: Colors.blueAccent.withOpacity(0.6),
                        backgroundColor: Colors.white24,
                        onSelected: (_) {
                          setState(() {
                            _extractedText = (_extractedText.isEmpty ? t : '$_extractedText $t');
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isCapturing ? null : _matchScannedText,
                          child: _isCapturing
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Confirm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _roundIconButton({required IconData icon, required VoidCallback onTap, String? tooltip}) {
  return Material(
    color: Colors.black.withOpacity(0.35),
    shape: const CircleBorder(),
    child: IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onTap,
      tooltip: tooltip,
    ),
  );
}

class _ReticlePainter extends CustomPainter {
  final Color color;
  _ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2.1),
      width: size.width * 0.74,
      height: size.height * 0.28,
    );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    canvas.drawRRect(rrect, paint);

    // Corner accents
    const corner = 18.0;
    // top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(corner, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, corner), paint);
    // top-right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-corner, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, corner), paint);
    // bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(corner, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -corner), paint);
    // bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-corner, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -corner), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
