import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';
import 'package:basta_fda/screens/not_found_screen.dart';
import 'package:basta_fda/screens/history_screen.dart';
import 'package:basta_fda/screens/settings_screen.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:basta_fda/services/settings_service.dart';

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
  // Removed _streaming flag (was unused)
  bool _isBusy = false;
  final bool _paused = false;
  bool _torchOn = false;
  bool _liveMode = false; // Lens-like live OCR (off by default)
  String _extractedText = "";
  List<String> _suggestions = [];
  Size? _imageSize;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  Timer? _debounce;
  bool _isCapturing = false;
  bool _showExtractedExpanded = false;
  String? _lastRawText; // keep last raw OCR text for Reg No extraction
  // Tap-to-focus + pinch-to-zoom
  Offset? _lastFocusTap;
  DateTime? _lastFocusAt;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoomForScale = 1.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    // Load user settings
    SettingsService.instance.load().then((_) {
      if (!mounted) return;
      setState(() {
        _liveMode = SettingsService.instance.liveOcrDefault;
      });
      // Auto-start/stop live OCR stream based on setting
      if (_liveMode) {
        _startStream();
      } else {
        _stopStream();
      }
    });
    // Ensure FDA data is loaded and reasonably fresh (uses cache first)
    widget.fdaChecker.ensureLoadedAndFresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    try {
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      // Set a gentle default zoom (helps OCR without blur)
      final desired = 1.5;
      _currentZoom = desired.clamp(_minZoom, _maxZoom);
      await _controller!.setZoomLevel(_currentZoom);
      await _controller!.setFocusMode(FocusMode.auto);
      try { await _controller!.setExposureMode(ExposureMode.auto); } catch (_) {}
    } catch (_) {}
    setState(() => _isInitialized = true);
    // Do not start stream by default to avoid ImageReader buffer pressure.
  }

  Future<void> _startStream() async {
    if (!mounted || _controller == null || _controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(_onImage);
  }

  Future<void> _stopStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
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

  // Prefer text within the reticle-like ROI; fallback to all text if too short
  String _composeTextFromResult(RecognizedText result) {
    if (result.blocks.isEmpty) return cleanText(result.text);
    double minX = double.infinity, minY = double.infinity, maxX = 0, maxY = 0;
    for (final b in result.blocks) {
      final r = b.boundingBox;
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }
    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();
    if (w <= 0 || h <= 0) return cleanText(result.text);

    // Main ROI centered; slightly shorter to reduce noise
    final roi = Rect.fromLTWH(minX + w * 0.2, minY + h * 0.33, w * 0.6, h * 0.30);
    // Footer strip to catch bottom lines (e.g., Reg. No.)
    final footer = Rect.fromLTWH(minX + w * 0.15, minY + h * 0.63, w * 0.70, h * 0.22);
    final buffer = StringBuffer();
    for (final block in result.blocks) {
      final box = block.boundingBox;
      if (roi.overlaps(box) || footer.overlaps(box)) {
        buffer.writeln(block.text);
      }
    }
    final focused = cleanText(buffer.toString());
    // Fallback to full text if ROI extraction is too short
    if (focused.split(' ').where((t) => t.isNotEmpty).length >= 2) {
      return focused;
    }
    return cleanText(result.text);
  }

  // Reliable still-shot scan used for Confirm action
  Future<String?> _scanFromPhoto() async {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return null;
    try {
      setState(() => _isCapturing = true);
      // Stop the stream before capture to avoid conflicts
      await _stopStream();

      // Autofocus pulse at center, small settle delay for sharpness
      try {
        final center = const Offset(0.5, 0.5);
        await _controller!.setFocusMode(FocusMode.auto);
        try { await _controller!.setExposureMode(ExposureMode.auto); } catch (_) {}
        await _controller!.setFocusPoint(center);
        await _controller!.setExposurePoint(center);
        // Small settle delay for AF/AE to converge
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (_) {}

      // Lock orientation during capture when possible to prevent rotation glitches
      try { await _controller!.lockCaptureOrientation(); } catch (_) {}

      final XFile file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);
      final rawText = result.text;
      _lastRawText = rawText;
      final scannedText = _composeTextFromResult(result);

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
        try { await _controller!.unlockCaptureOrientation(); } catch (_) {}
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
    // Honor setting: skip review if disabled
    final wantsReview = SettingsService.instance.reviewBeforeSearch;
    if (!wantsReview) {
      final text = await _scanFromPhoto();
      if (text != null && text.isNotEmpty) {
        await _executeSearch(text);
      }
      return;
    }
    await _reviewAndSearch();
  }

  Future<void> _reviewAndSearch({String? preset, bool capturePhoto = true}) async {
    // Start with preset or capture a fresh still for reliable OCR
    final first = capturePhoto ? await _scanFromPhoto() : preset;
    if (!mounted) return;
    String working = first ?? _extractedText;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final controller = TextEditingController(text: working);
        // Detect Reg. No. candidates from raw or current text
        final rawForReg = _lastRawText ?? working;
        final regCandidates = widget.fdaChecker.regCandidates(rawForReg);
        final padding = EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          left: 16,
          right: 16,
          top: 16,
        );
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: padding,
            child: SingleChildScrollView(
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
                  if (regCandidates.isNotEmpty) ...[
                    Text('Detected Reg. No.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: regCandidates.take(3).map((code) {
                        return ActionChip(
                          label: Text(code),
                          onPressed: () {
                            controller.text = code;
                            working = code;
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
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
            ),
          ),
        );
      },
    );
  }

  

  Future<void> _executeSearch(String text) async {
    // Prefer direct Reg. No. match using raw OCR (more reliable for patterns)
    final raw = _lastRawText ?? text;
    final byReg = widget.fdaChecker.findByRegNo(raw);
    // If a reg-like code is present but not found, avoid heuristic false positives
    final regLike = RegExp(r"\b[A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?\b").hasMatch(raw) ||
        RegExp(r"\breg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*[A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?\b", caseSensitive: false).hasMatch(raw);
    final matchedProduct = byReg ?? (regLike ? null : widget.fdaChecker.findProductDetailsWithExplain(text));
    if (!mounted) return;
    if (matchedProduct != null) {
      final eval = widget.fdaChecker.evaluateScan(raw: raw, product: matchedProduct);
      final status = eval.status;
      if (eval.reasons.isNotEmpty) {
        matchedProduct['verification_reasons'] = eval.reasons.join('\n');
      }
      await HistoryService.instance.addEntry(scannedText: text, productInfo: matchedProduct, status: status);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanResultScreen(
            productInfo: matchedProduct,
            status: status,
          ),
        ),
      );
    } else {
      await HistoryService.instance.addEntry(scannedText: raw, productInfo: null, status: 'NOT FOUND');
      if (!mounted) return;
      final returned = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NotFoundScreen(scannedText: raw, fdaChecker: widget.fdaChecker)),
      );
      if (!mounted) return;
      if (returned is String && returned.isNotEmpty) {
        setState(() => _extractedText = returned);
        final wantsReview = SettingsService.instance.reviewBeforeSearch;
        if (wantsReview) {
          await _reviewAndSearch(preset: returned, capturePhoto: false);
        } else {
          await _executeSearch(returned);
        }
      }
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
appBar: AppBar(
        title: const Text('Scan Product'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(fdaChecker: widget.fdaChecker))),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),

          // Gesture layer for tap-to-focus and pinch-to-zoom
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) async {
                if (_controller == null || !_controller!.value.isInitialized) return;
                final size = MediaQuery.of(context).size;
                final dx = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
                final dy = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
                try {
                  await _controller!.setFocusMode(FocusMode.auto);
                  await _controller!.setFocusPoint(Offset(dx, dy));
                  await _controller!.setExposurePoint(Offset(dx, dy));
                  HapticFeedback.selectionClick();
                  setState(() {
                    _lastFocusTap = details.localPosition;
                    _lastFocusAt = DateTime.now();
                  });
                } catch (_) {}
              },
              onScaleStart: (details) {
                _baseZoomForScale = _currentZoom;
              },
              onScaleUpdate: (details) async {
                if (_controller == null) return;
                final desired = (_baseZoomForScale * details.scale).clamp(_minZoom, _maxZoom);
                if ((desired - _currentZoom).abs() > 0.01) {
                  _currentZoom = desired;
                  try {
                    await _controller!.setZoomLevel(_currentZoom);
                  } catch (_) {}
                  setState(() {});
                }
              },
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ReticlePainter(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
          ),

          // Small banner to indicate FDA DB loading state or staleness
          if (!widget.fdaChecker.isLoaded)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text('Loading FDA data…', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            )
          else if (widget.fdaChecker.isStale)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('FDA data may be out of date. Open Settings to update.', style: TextStyle(color: Colors.orange))),
                  ],
                ),
              ),
            ),

          // (Multi-shot overlay removed)

          Positioned(
            top: 12,
            right: 12,
            child: _roundIconButton(
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
          ),

          // Focus ring indicator (briefly shown)
          if (_lastFocusTap != null && _lastFocusAt != null && DateTime.now().difference(_lastFocusAt!) < const Duration(seconds: 2))
            Positioned(
              left: _lastFocusTap!.dx - 22,
              top: _lastFocusTap!.dy - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: Colors.yellowAccent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
              child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
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
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Extracted Text', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              secondChild: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: Text(_extractedText, style: Theme.of(context).textTheme.bodyMedium),
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
                      return FilterChip(
                        label: Text(t),
                        selected: _extractedText.contains(t),
                        showCheckmark: false,
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
                          onPressed: _isCapturing || !widget.fdaChecker.isLoaded ? null : _matchScannedText,
                          child: _isCapturing
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(widget.fdaChecker.isLoaded ? 'Confirm' : 'Loading…'),
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
    color: Colors.black.withValues(alpha: 0.35),
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
