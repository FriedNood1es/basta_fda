import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:basta_fda/models/scan_verdict.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';
import 'package:basta_fda/screens/history_screen.dart';
import 'package:basta_fda/screens/settings_screen.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:basta_fda/services/image_classifier.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:basta_fda/data/packaging_trained_products.dart';
import 'package:image/image.dart' as img;

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;
  final bool cameraEnabled;

  const ScannerScreen({
    super.key,
    required this.cameras,
    required this.fdaChecker,
    this.cameraEnabled = true,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _CaptureStep { packaging, regNumber }

enum _ImageQuality { ok, borderline, fail }

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isMatching = false;
  bool _torchOn = false;
  bool _updatingFda = false;
  String _extractedText = "";
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  bool _isCapturing = false;
  String? _lastRawText; // keep last raw OCR text for Reg No extraction
  bool _scopeNoticeShown = false;
  bool _wideShotCaptured = false;
  bool _regShotCaptured = false;
  bool _pendingRegCapture = false;
  bool _showCaptureGuide = false;
  bool _packagingSummaryVisible = false;
  // Tap-to-focus + pinch-to-zoom
  Offset? _lastFocusTap;
  DateTime? _lastFocusAt;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoomForScale = 1.0;
  final PackagingImageClassifier _imageClassifier =
      PackagingImageClassifier.instance;
  static const double _minBrightness = 0.14; // relaxed brightness 0..1
  static const double _borderlineBrightness = 0.10;
  static const double _minSharpness = 10.0; // relaxed variance threshold
  static const double _borderlineSharpness = 6.5;
  String? _packagingImagePath;
  String? _regImagePath;
  String? _confirmedRegNumber;
  _CaptureStep _activeCaptureStep = _CaptureStep.packaging;
  bool _packageCaptureSkipped = false;
  bool _regCaptureSkipped = false;
  bool _regSelectionPending = false;
  String? _pendingRegText;
  String? _pendingRegRaw;
  PackagingModelCategory? _selectedCategory;
  bool _showCategorySelector = false;

  bool get _hasCompletedPackaging =>
      _packageCaptureSkipped || _wideShotCaptured;

  bool get _hasCompletedRegStep => _regCaptureSkipped || _regShotCaptured;
  bool get _hasSelectedCategory => _selectedCategory != null;

  bool get _canConfirmFlow =>
      widget.fdaChecker.isLoaded &&
      _hasCompletedPackaging &&
      _hasCompletedRegStep &&
      _hasSelectedCategory;
  @override
  void initState() {
    super.initState();
    if (widget.cameraEnabled) {
      _initCamera();
    } else {
      _isInitialized = true;
    }
    // Load user settings
    SettingsService.instance.load().then((_) {
      if (!mounted) return;
      // Ensure history is scoped to the current session (guest vs user)
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // ignore: discarded_futures
          HistoryService.instance.switchProfileKey(user.uid);
        } else if (SettingsService.instance.guestMode) {
          // ignore: discarded_futures
          HistoryService.instance.switchProfileKey('guest');
        }
      } catch (_) {}
      _maybeShowScopeNotice();
    });
    // Ensure FDA data is loaded and reasonably fresh (uses cache first)
    widget.fdaChecker.ensureLoadedAndFresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _maybeShowScopeNotice() {
    final settings = SettingsService.instance;
    if (_scopeNoticeShown || settings.hasSeenScopeNotice) return;
    _scopeNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || settings.hasSeenScopeNotice) return;
      await showModalBottomSheet<bool>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.help_outline_rounded, size: 18),
                      label: const Text('How to scan'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _showCaptureGuide = true);
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'How bastaFDA checks products',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We match the label text you scan against FDA registration records. We cannot confirm if packaging is genuine or tampered.',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      settings.hasSeenScopeNotice = true;
      await settings.save();
    });
  }

  void _resetCaptureFlow({bool clearText = false}) {
    setState(() {
      _wideShotCaptured = false;
      _regShotCaptured = false;
      _packageCaptureSkipped = false;
      _regCaptureSkipped = false;
      _pendingRegCapture = false;
      _activeCaptureStep = _CaptureStep.packaging;
      _packagingImagePath = null;
      _regImagePath = null;
      _regSelectionPending = false;
      _pendingRegText = null;
      _pendingRegRaw = null;
      _confirmedRegNumber = null;
      if (clearText) {
        _extractedText = '';
        _lastRawText = null;
      }
    });
  }

  Future<void> _handleScanResultReturn(Object? result) async {
    if (!mounted || result != ScanResultScreen.viewHistoryResult) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  Future<void> _refreshFdaData() async {
    if (_updatingFda) return;
    setState(() => _updatingFda = true);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Refreshing FDA database…',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
          ),
        );
      },
    );
    try {
      await widget.fdaChecker.ensureLoadedAndFresh();
      await widget.fdaChecker.loadCSVIsolatePreferCache();
    } finally {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (mounted) setState(() => _updatingFda = false);
    }
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
      try {
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}
    } catch (_) {}
    setState(() => _isInitialized = true);
    // Do not start stream by default to avoid ImageReader buffer pressure.
  }

  Future<void> _stopStream() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
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
    final roi = Rect.fromLTWH(
      minX + w * 0.18,
      minY + h * 0.30,
      w * 0.64,
      h * 0.34,
    );
    // Footer strip to catch bottom lines (e.g., Reg. No.)
    final footer = Rect.fromLTWH(
      minX + w * 0.10,
      minY + h * 0.54,
      w * 0.80,
      h * 0.38,
    );
    bool rectHasCoverage(Rect target, Rect box) {
      const tolerance = 16.0;
      final expanded = target.inflate(tolerance);
      if (!expanded.overlaps(box)) return false;
      final overlapLeft = expanded.left > box.left ? expanded.left : box.left;
      final overlapTop = expanded.top > box.top ? expanded.top : box.top;
      final overlapRight = expanded.right < box.right
          ? expanded.right
          : box.right;
      final overlapBottom = expanded.bottom < box.bottom
          ? expanded.bottom
          : box.bottom;
      final overlapWidth = overlapRight - overlapLeft;
      final overlapHeight = overlapBottom - overlapTop;
      if (overlapWidth <= 0 || overlapHeight <= 0) return false;
      final overlapArea = overlapWidth * overlapHeight;
      final boxArea = box.width * box.height;
      if (boxArea <= 0) return false;
      const minCoverage = 0.35;
      return overlapArea >= boxArea * minCoverage;
    }

    final buffer = StringBuffer();
    for (final block in result.blocks) {
      final box = block.boundingBox;
      if (rectHasCoverage(roi, box) || rectHasCoverage(footer, box)) {
        buffer.writeln(block.text);
      }
    }
    final rawFocused = buffer.toString();
    final focused = cleanText(rawFocused);
    final wordCount = focused.split(' ').where((t) => t.isNotEmpty).length;
    final fullRaw = result.text;

    if (widget.fdaChecker.regCandidates(rawFocused).isNotEmpty) {
      return focused;
    }
    if (widget.fdaChecker.regCandidates(fullRaw).isNotEmpty) {
      return cleanText(fullRaw);
    }
    if (wordCount >= 2) {
      return focused;
    }
    return cleanText(fullRaw);
  }

  // Reliable still-shot scan used for Confirm action
  Future<String?> _scanFromPhoto() async {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      return null;
    }
    try {
      setState(() => _isCapturing = true);
      // Stop the stream before capture to avoid conflicts
      await _stopStream();

      // Autofocus pulse at center, small settle delay for sharpness
      try {
        final center = const Offset(0.5, 0.5);
        await _controller!.setFocusMode(FocusMode.auto);
        try {
          await _controller!.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        await _controller!.setFocusPoint(center);
        await _controller!.setExposurePoint(center);
        // Small settle delay for AF/AE to converge
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (_) {}

      // Lock orientation during capture when possible to prevent rotation glitches
      try {
        await _controller!.lockCaptureOrientation();
      } catch (_) {}

      final XFile file = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText result = await _textRecognizer.processImage(
        inputImage,
      );
      final rawText = result.text;
      _lastRawText = rawText;
      final scannedText = _composeTextFromResult(result);

      debugPrint(
        '[OCR] raw (${rawText.length} chars): ${rawText.replaceAll('\n', ' ')}',
      );
      debugPrint('[OCR] cleaned (${scannedText.length} chars): $scannedText');

      if (!mounted) return scannedText;
      final bool treatAsRegCapture =
          _pendingRegCapture || _activeCaptureStep == _CaptureStep.regNumber;
      setState(() {
        _extractedText = scannedText;
        if (treatAsRegCapture) {
          _regShotCaptured = true;
          _pendingRegCapture = false;
          _activeCaptureStep = _CaptureStep.regNumber;
          _regImagePath = file.path;
        } else {
          _wideShotCaptured = true;
          _packagingImagePath = file.path;
          if (!_regShotCaptured && !_regCaptureSkipped) {
            _activeCaptureStep = _CaptureStep.regNumber;
          }
        }
      });
      return scannedText;
    } catch (e) {
      debugPrint('[OCR] photo scan error: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
        try {
          await _controller!.unlockCaptureOrientation();
        } catch (_) {}
      }
    }
  }

  Future<bool> _capturePackagingPhoto() async {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) {
      return false;
    }
    try {
      setState(() => _isCapturing = true);
      await _stopStream();

      try {
        final center = const Offset(0.5, 0.5);
        await _controller!.setFocusMode(FocusMode.auto);
        try {
          await _controller!.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        await _controller!.setFocusPoint(center);
        await _controller!.setExposurePoint(center);
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (_) {}

      try {
        await _controller!.lockCaptureOrientation();
      } catch (_) {}

      final XFile file = await _controller!.takePicture();
      final quality = await _evaluateImageQuality(file.path);
      if (quality == _ImageQuality.fail) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image looked too dark or blurry. Try again.'),
            ),
          );
        }
        return false;
      }
      if (quality == _ImageQuality.borderline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Capture saved but looked a bit dark/blurry. Turn on flash if OCR misses text.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() {
        _packagingImagePath = file.path;
        _wideShotCaptured = true;
        if (!_regShotCaptured && !_regCaptureSkipped) {
          _activeCaptureStep = _CaptureStep.regNumber;
        }
      });
      return true;
    } catch (e) {
      debugPrint('[PACKAGING] photo error: $e');
      return false;
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
        try {
          await _controller!.unlockCaptureOrientation();
        } catch (_) {}
      }
    }
  }

  Future<_ImageQuality> _evaluateImageQuality(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return _ImageQuality.ok; // fallback to allow
      final gray = img.grayscale(decoded);
      double sum = 0;
      for (final p in gray) {
        sum += img.getLuminance(p) / 255.0;
      }
      final mean = sum / gray.length;
      final bool brightEnough = mean >= _minBrightness;
      final bool brightBorderline = mean >= _borderlineBrightness;

      // Simple sharpness via Laplacian variance (sampled every 4px)
      double lapSum = 0;
      double lapSqSum = 0;
      int count = 0;
      final w = gray.width;
      final h = gray.height;
      for (int y = 1; y < h - 1; y += 4) {
        for (int x = 1; x < w - 1; x += 4) {
          final center = img.getLuminance(gray.getPixel(x, y)).toDouble();
          final lap =
              4 * center -
              img.getLuminance(gray.getPixel(x - 1, y)).toDouble() -
              img.getLuminance(gray.getPixel(x + 1, y)).toDouble() -
              img.getLuminance(gray.getPixel(x, y - 1)).toDouble() -
              img.getLuminance(gray.getPixel(x, y + 1)).toDouble();
          lapSum += lap;
          lapSqSum += lap * lap;
          count++;
        }
      }
      if (count == 0) return _ImageQuality.ok;
      final meanLap = lapSum / count;
      final variance = (lapSqSum / count) - (meanLap * meanLap);
      final bool sharpEnough = variance >= _minSharpness;
      final bool sharpBorderline = variance >= _borderlineSharpness;

      if (brightEnough && sharpEnough) return _ImageQuality.ok;
      if (brightBorderline && sharpBorderline) return _ImageQuality.borderline;
      return _ImageQuality.fail;
    } catch (_) {
      return _ImageQuality.ok;
    }
  }

  Future<void> _startPackagingCapture() async {
    if (_isCapturing) return;
    setState(() {
      _activeCaptureStep = _CaptureStep.packaging;
      _packageCaptureSkipped = false;
      _pendingRegCapture = false;
    });
    final success = await _capturePackagingPhoto();
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not capture packaging clearly. Try again.'),
        ),
      );
    }
  }

  Future<void> _startRegCapture() async {
    if (_isCapturing) return;
    setState(() {
      _activeCaptureStep = _CaptureStep.regNumber;
      _regCaptureSkipped = false;
      _pendingRegCapture = true;
    });
    final result = await _scanFromPhoto();
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reg capture looked unclear. Try again.')),
      );
      _pendingRegCapture = true;
      return;
    }
    _pendingRegText = result;
    _pendingRegRaw = _lastRawText ?? result;
    final accepted = await _promptRegSelection(
      initial: result,
      rawText: _pendingRegRaw ?? result,
    );
    if (!mounted) return;
    if (!accepted) {
      _pendingRegCapture = true;
      return;
    }
    _pendingRegCapture = false;
  }

  void _skipPackagingCapture() {
    setState(() {
      _packageCaptureSkipped = true;
      _wideShotCaptured = false;
      _activeCaptureStep = _CaptureStep.regNumber;
      _pendingRegCapture = !_regShotCaptured;
    });
  }

  void _resumePackagingCapture() {
    setState(() {
      _packageCaptureSkipped = false;
      _activeCaptureStep = _CaptureStep.packaging;
      _pendingRegCapture = false;
    });
  }

  void _skipRegCapture() {
    setState(() {
      _regCaptureSkipped = true;
      _regShotCaptured = false;
      _activeCaptureStep = _CaptureStep.regNumber;
      _pendingRegCapture = false;
    });
  }

  void _resumeRegCapture() {
    setState(() {
      _regCaptureSkipped = false;
      _activeCaptureStep = _CaptureStep.regNumber;
    });
  }

  Future<bool> _promptRegSelection({
    required String initial,
    required String rawText,
    bool allowRetake = true,
  }) async {
    _regSelectionPending = true;
    final selection = await _showRegSelectionSheet(
      initialText: initial,
      rawText: rawText,
      allowRetake: allowRetake,
    );
    if (!mounted) return false;
    if (selection == null) {
      _regSelectionPending = false;
      return false;
    }
    setState(() {
      _confirmedRegNumber = selection;
      _regShotCaptured = true;
      _regCaptureSkipped = false;
      _regSelectionPending = false;
    });
    return true;
  }

  Future<void> _confirmScan() async {
    if (!_ensureCategorySelected()) return;
    if (!_canConfirmFlow || _isCapturing || _isMatching) return;
    if (!_regCaptureSkipped &&
        (_confirmedRegNumber == null || _pendingRegCapture)) {
      final selected = await _promptRegSelection(
        initial: _pendingRegText ?? _extractedText ?? '',
        rawText: _pendingRegRaw ?? _lastRawText ?? _extractedText ?? '',
        allowRetake: true,
      );
      if (!selected) return;
    }
    await _matchScannedText();
  }

  Future<void> _matchScannedText() async {
    final wantsReview = SettingsService.instance.reviewBeforeSearch;
    final bool regSkipped = _regCaptureSkipped;

    if (!_ensureCategorySelected()) return;

    if (!wantsReview) {
      if (regSkipped) {
        await _executeSearch(
          '',
          rawOverride: '',
          skipImageCheck: _packageCaptureSkipped,
        );
        return;
      }
      if (_confirmedRegNumber != null &&
          !_pendingRegCapture &&
          !_regSelectionPending) {
        await _executeSearch(
          _confirmedRegNumber!,
          rawOverride: _confirmedRegNumber!,
          skipImageCheck: _packageCaptureSkipped,
        );
        return;
      }
      final text = await _scanFromPhoto();
      if (text != null && text.isNotEmpty) {
        await _executeSearch(text, skipImageCheck: false);
      }
      return;
    }

    await _reviewAndSearch(
      capturePhoto: !regSkipped,
      preset: regSkipped ? '' : null,
      rawOverride: regSkipped ? '' : null,
      allowImageCheck: true,
    );
  }

  Future<void> _reviewAndSearch({
    String? preset,
    String? rawOverride,
    bool capturePhoto = true,
    bool allowImageCheck = true,
  }) async {
    if (!_ensureCategorySelected()) return;
    if (_regCaptureSkipped) {
      await _executeSearch(
        preset ?? '',
        rawOverride: rawOverride ?? '',
        skipImageCheck: !allowImageCheck || _packageCaptureSkipped,
      );
      return;
    }

    if (_confirmedRegNumber != null &&
        !_pendingRegCapture &&
        !_regSelectionPending) {
      await _executeSearch(
        _confirmedRegNumber!,
        rawOverride: _confirmedRegNumber!,
        skipImageCheck: !allowImageCheck || _packageCaptureSkipped,
      );
      return;
    }

    // Start with preset or capture a fresh still for reliable OCR
    final first = capturePhoto ? await _scanFromPhoto() : preset;
    if (!mounted) return;
    String working = first ?? _extractedText;

    final rawForReg = rawOverride ?? _lastRawText ?? working;
    final selected = await _promptRegSelection(
      initial: working,
      rawText: rawForReg,
      allowRetake: true,
    );
    if (!mounted) return;
    if (!selected || _confirmedRegNumber == null) return;
    await _executeSearch(
      _confirmedRegNumber!,
      rawOverride: _confirmedRegNumber!,
      skipImageCheck: !allowImageCheck || _packageCaptureSkipped,
    );
  }

  Future<void> _executeSearch(
    String text, {
    String? rawOverride,
    bool skipImageCheck = false,
  }) async {
    if (_isMatching) return;
    _isMatching = true;
    bool dialogShown = false;

    Future<ImageCheckResult> resolveImageCheck(String rawText) {
      if (skipImageCheck) {
        return Future.value(
          const ImageCheckResult(status: ImageCheckStatus.skipped),
        );
      }
      final category = _selectedCategory;
      if (category == null) {
        debugPrint('Packaging helper skipped: category not selected');
        return Future.value(
          const ImageCheckResult(status: ImageCheckStatus.failed),
        );
      }
      try {
        return _imageClassifier
            .classify(
              rawText: rawText,
              additionalText: text,
              imagePath: _packagingImagePath,
              category: category,
            )
            .then((prediction) {
              if (prediction == null) {
                debugPrint('Packaging helper: no prediction');
                return const ImageCheckResult(
                  status: ImageCheckStatus.unrecognized,
                );
              }
              final info = prediction.toMap();
              final productName = info['product'] ?? 'unknown';
              final confidenceText = info['confidence'] ?? '?';
              debugPrint(
                'Packaging helper result: ' +
                    productName +
                    ' (confidence ' +
                    confidenceText +
                    ')',
              );
              return ImageCheckResult(
                status: ImageCheckStatus.recognized,
                info: info,
              );
            })
            .catchError((error) {
              debugPrint('Packaging helper failed: ' + error.toString());
              return const ImageCheckResult(status: ImageCheckStatus.failed);
            });
      } catch (_) {
        return Future.value(
          const ImageCheckResult(status: ImageCheckStatus.failed),
        );
      }
    }

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _MatchingDialog(),
        );
        dialogShown = true;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final trimmedInput = text.trim();
      final raw = (rawOverride ?? _lastRawText ?? text).trim();
      _confirmedRegNumber =
          _extractRegNumber(trimmedInput) ?? _extractRegNumber(raw);

      final byReg = widget.fdaChecker.findByRegNo(raw);
      final regLike =
          RegExp(r'\b[A-Za-z]{2,4}-\d{3,6}(?:-\d{2,4})?\b').hasMatch(raw) ||
          RegExp(
            r'\breg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*[A-Za-z]{2,4}-\d{3,6}(?:-\d{2,4})?\b',
            caseSensitive: false,
          ).hasMatch(raw);

      Map<String, String>? matchedProduct;
      if (byReg != null) {
        matchedProduct = byReg;
      } else if (!regLike) {
        matchedProduct = await widget.fdaChecker
            .findProductDetailsWithExplainAsync(text);
      }

      if (!mounted) return;

      late final Future<ImageCheckResult> imageResultFuture;
      late final ImageCheckResult initialImageResult;
      Map<String, String>? nonNullProduct;
      bool isImageTrainedProduct = false;

      if (matchedProduct != null) {
        nonNullProduct = Map<String, String>.from(matchedProduct);
        isImageTrainedProduct = PackagingCoverage.matchesProduct(
          nonNullProduct,
        );

        if (skipImageCheck) {
          imageResultFuture = Future.value(
            const ImageCheckResult(status: ImageCheckStatus.skipped),
          );
          initialImageResult = const ImageCheckResult(
            status: ImageCheckStatus.skipped,
          );
        } else if (!isImageTrainedProduct) {
          imageResultFuture = Future.value(
            const ImageCheckResult(status: ImageCheckStatus.unrecognized),
          );
          initialImageResult = const ImageCheckResult(
            status: ImageCheckStatus.unrecognized,
          );
        } else {
          imageResultFuture = resolveImageCheck(raw);
          initialImageResult = const ImageCheckResult(
            status: ImageCheckStatus.pending,
          );
        }

        final eval = widget.fdaChecker.evaluateScan(
          raw: raw,
          product: nonNullProduct,
        );
        final status = eval.status;
        if (eval.reasons.isNotEmpty) {
          nonNullProduct['verification_reasons'] = eval.reasons.join('\n');
        }
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.of(context).pop();
          dialogShown = false;
          await Future<void>.delayed(Duration.zero);
        }
        if (!mounted) return;
        if (status.toUpperCase() == 'UNRECOGNIZED') {
          final List<String> reasonsText = eval.reasons.isNotEmpty
              ? eval.reasons
              : ['Possible mismatch between scan and FDA record'];
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              return AlertDialog(
                title: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('ALERT'),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'The product appears to be UNRECOGNIZED based on the following:',
                      ),
                      const SizedBox(height: 12),
                      ...reasonsText.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('- $r'),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('View Details'),
                  ),
                ],
              );
            },
          );
        }

        final registrationStatus = RegistrationStatus.registered;
        final historyProduct = Map<String, String>.from(nonNullProduct);
        final capturedPackagingPath = _packagingImagePath;
        unawaited(
          imageResultFuture.then((imageResult) async {
            await HistoryService.instance.addEntry(
              scannedText: text,
              productInfo: historyProduct,
              status: status,
              imageInfo: imageResult.info,
              registrationStatus: registrationStatus,
              imageStatus: imageResult.status,
              regNumber: _confirmedRegNumber,
              imageTrainedProduct: isImageTrainedProduct,
              packagingImagePath: capturedPackagingPath,
            );
          }),
        );

        if (!mounted) return;
        final navResult = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanResultScreen(
              productInfo: nonNullProduct!,
              status: status,
              registrationStatus: registrationStatus,
              initialImageResult: initialImageResult,
              imageResultFuture: imageResultFuture,
              confirmedRegNumber: _confirmedRegNumber,
              packagingImagePath: capturedPackagingPath,
              isImageTrainedProduct: isImageTrainedProduct,
            ),
          ),
        );
        _resetCaptureFlow(clearText: true);
        await _handleScanResultReturn(navResult);
      } else {
        if (skipImageCheck) {
          imageResultFuture = Future.value(
            const ImageCheckResult(status: ImageCheckStatus.skipped),
          );
          initialImageResult = const ImageCheckResult(
            status: ImageCheckStatus.skipped,
          );
        } else {
          imageResultFuture = resolveImageCheck(raw);
          initialImageResult = const ImageCheckResult(
            status: ImageCheckStatus.pending,
          );
        }

        if (dialogShown && Navigator.canPop(context)) {
          Navigator.of(context).pop();
          dialogShown = false;
          await Future<void>.delayed(Duration.zero);
        }
        final capturedPackagingPath = _packagingImagePath;
        final imageResult = await imageResultFuture;
        final imageRecognized =
            imageResult.status == ImageCheckStatus.recognized;

        if (imageRecognized) {
          final info = imageResult.info ?? {};
          final productName = (info['product']?.trim().isNotEmpty ?? false)
              ? info['product']!.trim()
              : 'Packaging match';
          final verdict = info['verdict'];
          final matchReason = _regCaptureSkipped
              ? 'Packaging helper recognized this product.'
              : 'Packaging helper recognized this product, but no FDA record matched the scan.';
          final pseudoProduct = <String, String>{
            'brand_name': productName,
            'generic_name': productName,
            'match_reason': matchReason,
            'packaging_category': _categoryLabel(_selectedCategory),
          };
          if (verdict != null && verdict.isNotEmpty) {
            pseudoProduct['verification_reasons'] =
                'Image verdict: ${verdict[0].toUpperCase()}${verdict.substring(1)}';
          }
          await HistoryService.instance.addEntry(
            scannedText: raw,
            productInfo: pseudoProduct,
            status: 'IMAGE_ONLY',
            imageInfo: info,
            registrationStatus: RegistrationStatus.unregistered,
            imageStatus: imageResult.status,
            regNumber: _confirmedRegNumber,
            imageTrainedProduct: true,
            packagingImagePath: capturedPackagingPath,
          );
          if (!mounted) return;
          final navResult = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScanResultScreen(
                productInfo: pseudoProduct,
                status: 'IMAGE_ONLY',
                registrationStatus: RegistrationStatus.unregistered,
                initialImageResult: imageResult,
                imageResultFuture: null,
                confirmedRegNumber: _confirmedRegNumber,
                packagingImagePath: capturedPackagingPath,
                isImageTrainedProduct: true,
              ),
            ),
          );
          _resetCaptureFlow(clearText: false);
          await _handleScanResultReturn(navResult);
        } else {
          await HistoryService.instance.addEntry(
            scannedText: raw,
            productInfo: null,
            status: 'NOT FOUND',
            imageInfo: imageResult.info,
            registrationStatus: RegistrationStatus.unregistered,
            imageStatus: imageResult.status,
            regNumber: _confirmedRegNumber,
            packagingImagePath: capturedPackagingPath,
          );
          if (!mounted) return;
          setState(() => _extractedText = raw);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No FDA match found. Edit the text or scan again.'),
            ),
          );
        }
      }
    } finally {
      if (mounted && dialogShown && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      _isMatching = false;
    }
  }

  String cleanText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _extractRegNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final regPattern = RegExp(
      r'([A-Za-z]{2,4}(?:-[A-Za-z]{1,4})?-\d{3,6}(?:-\d{2,4})?|[A-Za-z]{2,4}(?:[\s-]?[A-Za-z]{1,4})?[\s-]?\d{3,6}(?:[\s-]?\d{2,4})?)',
    );
    final verbosePattern = RegExp(
      r'reg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*([A-Za-z]{2,4}(?:-[A-Za-z]{1,4})?-\d{3,6}(?:-\d{2,4})?|[A-Za-z]{2,4}(?:[\s-]?[A-Za-z]{1,4})?[\s-]?\d{3,6}(?:[\s-]?\d{2,4})?)',
      caseSensitive: false,
    );
    final direct = regPattern.firstMatch(trimmed);
    if (direct != null) return direct.group(1)?.toUpperCase();
    final verbose = verbosePattern.firstMatch(trimmed);
    if (verbose != null) return verbose.group(1)?.toUpperCase();
    return null;
  }

  Future<String?> _showRegSelectionSheet({
    required String initialText,
    required String rawText,
    bool allowRetake = true,
  }) async {
    final controller = TextEditingController(text: initialText.trim());
    String? error;
    final candidates = widget.fdaChecker.regCandidates(rawText);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: allowRetake,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Choose registration number',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (allowRetake)
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (candidates.isNotEmpty) ...[
                      Text(
                        'Suggestions from scan',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: candidates.take(4).map((code) {
                          return ActionChip(
                            label: Text(code),
                            onPressed: () {
                              setSheetState(() {
                                controller.text = code;
                                error = null;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Text(
                        'We could not detect a clear reg. number. Enter it manually or retake.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Reg. number',
                        hintText: 'ABC-123456',
                        errorText: error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: allowRetake
                              ? () => Navigator.of(ctx).pop(null)
                              : null,
                          icon: const Icon(Icons.cameraswitch_rounded),
                          label: const Text('Retake reg capture'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final normalized = _extractRegNumber(
                              controller.text,
                            );
                            if (normalized == null) {
                              setSheetState(() {
                                error =
                                    'Enter a valid reg. number like DR-153 or ABC-123456.';
                              });
                              return;
                            }
                            Navigator.of(ctx).pop(normalized);
                          },
                          child: const Text('Use this number'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _stopStream();
    _textRecognizer.close();
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildCategorySelector() {
    return Positioned(
      top: 64,
      left: 12,
      right: 12,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: PackagingModelCategory.values.map((category) {
            final selected = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_categoryLabel(category)),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _categoryLabel(PackagingModelCategory? category) {
    if (category == null) return 'Select category';
    switch (category) {
      case PackagingModelCategory.food:
        return 'Food';
      case PackagingModelCategory.cosmetics:
        return 'Cosmetics';
      case PackagingModelCategory.supplements:
        return 'Supplements';
      case PackagingModelCategory.medicine:
        return 'Medicine';
    }
  }

  bool _ensureCategorySelected() {
    if (_selectedCategory != null) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a category before scanning.')),
    );
    if (!_showCategorySelector) {
      setState(() => _showCategorySelector = true);
    }
    return false;
  }

  bool get _canUseRegStep => _packageCaptureSkipped || _wideShotCaptured;

  void _selectCaptureStep(_CaptureStep step) {
    if (_activeCaptureStep == step) return;
    if (step == _CaptureStep.regNumber && !_canUseRegStep) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture packaging before the reg step.')),
      );
      return;
    }
    setState(() {
      _activeCaptureStep = step;
      if (step == _CaptureStep.regNumber) {
        _pendingRegCapture = !_regShotCaptured;
      } else {
        _pendingRegCapture = false;
      }
    });
  }

  Widget _buildStepTabs() {
    final bool regEnabled = _canUseRegStep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('Packaging'),
            selected: _activeCaptureStep == _CaptureStep.packaging,
            onSelected: (_) => _selectCaptureStep(_CaptureStep.packaging),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Reg number'),
            selected: _activeCaptureStep == _CaptureStep.regNumber,
            onSelected: regEnabled
                ? (_) => _selectCaptureStep(_CaptureStep.regNumber)
                : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.cameraEnabled) {
      return Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('Scan Product')),
        body: const Center(child: Text('Camera disabled in test mode')),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Scan Product'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(fdaChecker: widget.fdaChecker),
              ),
            ),
          ),
          IconButton(
            tooltip: _showCategorySelector
                ? 'Hide categories'
                : 'Select category',
            icon: Icon(
              _showCategorySelector ? Icons.category : Icons.category_outlined,
            ),
            onPressed: () {
              setState(() => _showCategorySelector = !_showCategorySelector);
            },
          ),
          IconButton(
            tooltip: 'How to scan',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => setState(() => _showCaptureGuide = true),
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
                if (_controller == null || !_controller!.value.isInitialized) {
                  return;
                }
                final size = MediaQuery.of(context).size;
                final dx = (details.localPosition.dx / size.width).clamp(
                  0.0,
                  1.0,
                );
                final dy = (details.localPosition.dy / size.height).clamp(
                  0.0,
                  1.0,
                );
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
                final desired = (_baseZoomForScale * details.scale).clamp(
                  _minZoom,
                  _maxZoom,
                );
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

          // Small banner to indicate FDA DB loading state or staleness
          if (!widget.fdaChecker.isLoaded)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading FDA data?',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (widget.fdaChecker.isStale)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: GestureDetector(
                onTap: _updatingFda ? null : () async => _refreshFdaData(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'FDA data may be out of date. Tap to update now.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_showCategorySelector || !_hasSelectedCategory)
            _buildCategorySelector(),

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
                  await _controller!.setFlashMode(
                    _torchOn ? FlashMode.torch : FlashMode.off,
                  );
                  setState(() {});
                } catch (_) {}
              },
            ),
          ),

          // Focus ring indicator (briefly shown)
          if (_lastFocusTap != null &&
              _lastFocusAt != null &&
              DateTime.now().difference(_lastFocusAt!) <
                  const Duration(seconds: 2))
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
            child: _buildCaptureControlsOverlay(context),
          ),
          if (_showCaptureGuide)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showCaptureGuide = false),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.camera_alt_rounded, size: 26),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'How scanning works',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _showCaptureGuide = false),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const _GuideStep(
                              number: '1',
                              title: 'Capture the packaging (optional)',
                              body:
                                  'Take a clear photo of the label if your product is in our trained references so the app can compare packaging cues.',
                            ),
                            const SizedBox(height: 12),
                            const _GuideStep(
                              number: '2',
                              title: 'Zoom into the registration number',
                              body:
                                  'Move closer or pinch-to-zoom on the printed FDA registration code so OCR can read it clearly. Retry if the capture looks blurry.',
                            ),
                            const SizedBox(height: 12),
                            const _GuideStep(
                              number: '3',
                              title: 'Confirm the scan',
                              body:
                                  'After both steps are captured or skipped, tap Confirm. We match the text against FDA records and use the packaging helper if available.',
                            ),
                            const SizedBox(height: 12),
                            const _GuideStep(
                              number: '4',
                              title: 'Using the reg number',
                              body:
                                  'If you tap "Use this number" in the selection sheet, we search with that code directly—no extra photo or OCR.',
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () =>
                                    setState(() => _showCaptureGuide = false),
                                child: const Text('Got it'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureControlsOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final bool categorySelected = _hasSelectedCategory;
    final bool isPackaging = _activeCaptureStep == _CaptureStep.packaging;
    final bool hasCapture = isPackaging ? _wideShotCaptured : _regShotCaptured;
    final bool skipped = isPackaging
        ? _packageCaptureSkipped
        : _regCaptureSkipped;
    final bool disabled = _isCapturing || _isMatching || !categorySelected;

    final IconData captureIcon = isPackaging
        ? Icons.camera_alt_rounded
        : Icons.document_scanner_rounded;
    final IconData primaryIcon = hasCapture
        ? Icons.refresh_rounded
        : captureIcon;
    final String primaryLabel = !categorySelected
        ? 'Select category'
        : hasCapture
        ? (isPackaging ? 'Retake packaging photo' : 'Retake reg photo')
        : (isPackaging ? 'Capture packaging photo' : 'Capture reg number');
    final VoidCallback? primaryAction = disabled
        ? null
        : (isPackaging ? _startPackagingCapture : _startRegCapture);

    final IconData skipIcon = skipped
        ? Icons.undo_rounded
        : Icons.visibility_off_rounded;
    final String skipLabel = skipped
        ? (isPackaging ? 'Use packaging capture' : 'Use reg capture')
        : (isPackaging ? 'Skip packaging' : 'Skip reg capture');
    final VoidCallback? skipAction = disabled
        ? null
        : (isPackaging
              ? (skipped ? _resumePackagingCapture : _skipPackagingCapture)
              : (skipped ? _resumeRegCapture : _skipRegCapture));

    final String stepTitle = isPackaging
        ? 'Step 1 - Packaging'
        : 'Step 2 - Registration';
    final String statusText = !categorySelected
        ? 'Select a category to start scanning'
        : skipped
        ? (isPackaging
              ? 'Skipped (image-only scan)'
              : 'Skipped (uses packaging text)')
        : hasCapture
        ? 'Capture saved'
        : 'Ready to capture';

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepTabs(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  stepTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: primaryAction,
                  icon: Icon(primaryIcon),
                  label: Text(primaryLabel),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: skipAction,
                  icon: Icon(skipIcon),
                  label: Text(skipLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                ),
                if (!_canUseRegStep && isPackaging)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Capture or skip packaging to unlock the reg step.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_canConfirmFlow)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                onPressed: _isMatching ? null : _confirmScan,
                icon: _isMatching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_isMatching ? 'Matching...' : 'Confirm scan'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _roundIconButton({
  required IconData icon,
  required VoidCallback onTap,
  String? tooltip,
}) {
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

class _GuideStep extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapturePreviewButton extends StatelessWidget {
  final String path;
  final String label;
  final IconData icon;

  const _CapturePreviewButton({
    required this.path,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path), fit: BoxFit.cover),
              ),
            ),
          );
        },
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _CaptureSummaryRow extends StatelessWidget {
  final bool packagingDone;
  final bool regDone;

  const _CaptureSummaryRow({
    required this.packagingDone,
    required this.regDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _CaptureSummaryPill(
          label: 'Packaging',
          icon: Icons.inventory_2_rounded,
          done: packagingDone,
          theme: theme,
        ),
        const SizedBox(width: 8),
        _CaptureSummaryPill(
          label: 'Reg number',
          icon: Icons.confirmation_number_rounded,
          done: regDone,
          theme: theme,
        ),
      ],
    );
  }
}

class _CaptureSummaryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool done;
  final ThemeData theme;

  const _CaptureSummaryPill({
    required this.label,
    required this.icon,
    required this.done,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = done ? Colors.greenAccent : Colors.white70;
    final Color fill = done
        ? Colors.greenAccent.withAlpha(40)
        : Colors.white.withAlpha(20);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              done ? '$label ✓' : '$label …',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchingDialog extends StatelessWidget {
  const _MatchingDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 14),
            Text(
              'Matching product...',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
