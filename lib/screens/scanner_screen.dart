import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final FDAChecker fdaChecker;

  const ScannerScreen({
    super.key,
    required this.cameras,
    required this.fdaChecker,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _CaptureStep { packaging, regNumber }

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isMatching = false;
  bool _torchOn = false;
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
  // Tap-to-focus + pinch-to-zoom
  Offset? _lastFocusTap;
  DateTime? _lastFocusAt;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoomForScale = 1.0;
  final PackagingImageClassifier _imageClassifier =
      PackagingImageClassifier.instance;
  String? _lastCapturedImagePath;
  String? _confirmedRegNumber;
  _CaptureStep _activeCaptureStep = _CaptureStep.packaging;
  bool _packageCaptureSkipped = false;
  bool _regCaptureSkipped = false;

  bool get _hasCompletedPackaging =>
      _packageCaptureSkipped || _wideShotCaptured;

  bool get _hasCompletedRegStep =>
      _regCaptureSkipped || _regShotCaptured;

  bool get _canConfirmFlow =>
      widget.fdaChecker.isLoaded &&
      _hasCompletedPackaging &&
      _hasCompletedRegStep;
  @override
  void initState() {
    super.initState();
    _initCamera();
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
      _lastCapturedImagePath = null;
      if (clearText) {
        _extractedText = '';
        _lastRawText = null;
      }
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
      _lastCapturedImagePath = file.path;
      final inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText result = await _textRecognizer.processImage(
        inputImage,
      );
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
      final bool treatAsRegCapture =
          _pendingRegCapture || _activeCaptureStep == _CaptureStep.regNumber;
      setState(() {
        _extractedText = scannedText;
        if (treatAsRegCapture) {
          _regShotCaptured = true;
          _pendingRegCapture = false;
          _activeCaptureStep = _CaptureStep.regNumber;
        } else {
          _wideShotCaptured = true;
          if (!_regShotCaptured && !_regCaptureSkipped) {
            _activeCaptureStep = _CaptureStep.regNumber;
          }
        }
      });
      return scannedText;
    } catch (e) {
      debugPrint('OCR photo scan error: $e');
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

  Future<void> _startPackagingCapture() async {
    if (_isCapturing) return;
    setState(() {
      _activeCaptureStep = _CaptureStep.packaging;
      _packageCaptureSkipped = false;
      _pendingRegCapture = false;
    });
    final result = await _scanFromPhoto();
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      if (!_regShotCaptured && !_regCaptureSkipped) {
        setState(() => _activeCaptureStep = _CaptureStep.regNumber);
      }
    } else {
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
        const SnackBar(
          content: Text('Reg capture looked unclear. Try again.'),
        ),
      );
    }
  }

  void _skipPackagingCapture() {
    setState(() {
      _packageCaptureSkipped = true;
      _wideShotCaptured = false;
      _activeCaptureStep = _CaptureStep.regNumber;
    });
  }

  void _resumePackagingCapture() {
    setState(() {
      _packageCaptureSkipped = false;
      _activeCaptureStep = _CaptureStep.packaging;
    });
  }

  void _skipRegCapture() {
    setState(() {
      _regCaptureSkipped = true;
      _regShotCaptured = false;
      _activeCaptureStep = _CaptureStep.regNumber;
    });
  }

  void _resumeRegCapture() {
    setState(() {
      _regCaptureSkipped = false;
      _activeCaptureStep = _CaptureStep.regNumber;
    });
  }

  Future<void> _confirmScan() async {
    if (!_canConfirmFlow || _isCapturing || _isMatching) return;
    await _matchScannedText();
  }

  Future<void> _matchScannedText() async {
    // Honor setting: skip review if disabled
    final wantsReview = SettingsService.instance.reviewBeforeSearch;
    if (!wantsReview) {
      final text = await _scanFromPhoto();
      if (text != null && text.isNotEmpty) {
        await _executeSearch(text, skipImageCheck: false);
      }
      return;
    }
    await _reviewAndSearch();
  }

  Future<void> _reviewAndSearch({
    String? preset,
    String? rawOverride,
    bool capturePhoto = true,
    bool allowImageCheck = true,
  }) async {
    // Start with preset or capture a fresh still for reliable OCR
    final first = capturePhoto ? await _scanFromPhoto() : preset;
    if (!mounted) return;
    String working = first ?? _extractedText;

    if (_regCaptureSkipped) {
      await _executeSearch(
        working,
        rawOverride: rawOverride ?? _lastRawText ?? working,
        skipImageCheck: !allowImageCheck || _packageCaptureSkipped,
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bool imageAllowed = allowImageCheck;
        // Detect Reg. No. candidates from raw or current text
        final rawForReg = rawOverride ?? _lastRawText ?? working;
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
                  const Text(
                    'Choose Registration Number',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (regCandidates.isNotEmpty) ...[
                    Text(
                      'Detected numbers',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: regCandidates.take(3).map((code) {
                        return ActionChip(
                          label: Text(code),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _executeSearch(
                              code,
                              rawOverride: code,
                              skipImageCheck: !imageAllowed,
                            );
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    const Text(
                      'No clear registration number detected.\nCapture another angle for clearer text.',
                    ),
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
                          final manual = (regCandidates.isNotEmpty
                                  ? regCandidates.first
                                  : working)
                              .trim();
                          _executeSearch(
                            manual,
                            rawOverride: manual,
                            skipImageCheck: !imageAllowed,
                          );
                        },
                        icon: const Icon(Icons.search_rounded),
                        label: Text(
                          regCandidates.isNotEmpty
                              ? 'Use top match'
                              : 'Use extracted text',
                        ),
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
      try {
        return _imageClassifier
            .classify(
              rawText: rawText,
              additionalText: text,
              imagePath: _lastCapturedImagePath,
            )
            .then((prediction) {
          if (prediction == null) {
            return const ImageCheckResult(
              status: ImageCheckStatus.unrecognized,
            );
          }
          return ImageCheckResult(
            status: ImageCheckStatus.recognized,
            info: prediction.toMap(),
          );
        }).catchError(
          (_) => const ImageCheckResult(status: ImageCheckStatus.failed),
        );
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
      if (trimmedInput.isNotEmpty) {
        _confirmedRegNumber = trimmedInput;
      } else if (raw.isNotEmpty) {
        _confirmedRegNumber = raw;
      }

      final byReg = widget.fdaChecker.findByRegNo(raw);
      final regLike =
          RegExp(r'\b[A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?\b').hasMatch(raw) ||
              RegExp(
                r'\breg(?:istration)?\.?\s*(?:no\.?|number)\s*[:#-]?\s*[A-Za-z]{3,4}-\d{3,6}(?:-\d{2,4})?\b',
                caseSensitive: false,
              ).hasMatch(raw);

      Map<String, String>? matchedProduct;
      if (byReg != null) {
        matchedProduct = byReg;
      } else if (!regLike) {
        matchedProduct =
            await widget.fdaChecker.findProductDetailsWithExplainAsync(text);
      }

      if (!mounted) return;

      late final Future<ImageCheckResult> imageResultFuture;
      late final ImageCheckResult initialImageResult;
      Map<String, String>? nonNullProduct;
      bool isImageTrainedProduct = false;

      if (matchedProduct != null) {
        nonNullProduct = Map<String, String>.from(matchedProduct);
        isImageTrainedProduct =
            PackagingCoverage.matchesProduct(nonNullProduct);

        if (skipImageCheck) {
          imageResultFuture = Future.value(
              const ImageCheckResult(status: ImageCheckStatus.skipped));
          initialImageResult =
              const ImageCheckResult(status: ImageCheckStatus.skipped);
        } else if (!isImageTrainedProduct) {
          imageResultFuture = Future.value(
              const ImageCheckResult(status: ImageCheckStatus.unrecognized));
          initialImageResult =
              const ImageCheckResult(status: ImageCheckStatus.unrecognized);
        } else {
          imageResultFuture = resolveImageCheck(raw);
          initialImageResult =
              const ImageCheckResult(status: ImageCheckStatus.pending);
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
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                    ),
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
            );
          }),
        );

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanResultScreen(
              productInfo: nonNullProduct!,
              status: status,
              registrationStatus: registrationStatus,
              initialImageResult: initialImageResult,
              imageResultFuture: imageResultFuture,
              confirmedRegNumber: _confirmedRegNumber,
              isImageTrainedProduct: isImageTrainedProduct,
            ),
          ),
        );
        _resetCaptureFlow(clearText: true);
      } else {
        if (skipImageCheck) {
          imageResultFuture = Future.value(
              const ImageCheckResult(status: ImageCheckStatus.skipped));
          initialImageResult =
              const ImageCheckResult(status: ImageCheckStatus.skipped);
        } else {
          imageResultFuture = resolveImageCheck(raw);
          initialImageResult =
              const ImageCheckResult(status: ImageCheckStatus.pending);
        }

        if (dialogShown && Navigator.canPop(context)) {
          Navigator.of(context).pop();
          dialogShown = false;
          await Future<void>.delayed(Duration.zero);
        }
        final imageResult = await imageResultFuture;
        final imageRecognized = imageResult.status == ImageCheckStatus.recognized &&
            (imageResult.info?['product']?.isNotEmpty ?? false);

        if (_regCaptureSkipped && imageRecognized) {
          final info = imageResult.info ?? {};
          final productName = info['product'] ?? 'Packaging match';
          final verdict = info['verdict'];
          final pseudoProduct = <String, String>{
            'brand_name': productName,
            'generic_name': productName,
            'match_reason': 'Packaging helper recognized this product.',
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
          );
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScanResultScreen(
                productInfo: pseudoProduct,
                status: 'IMAGE_ONLY',
                registrationStatus: RegistrationStatus.unregistered,
                initialImageResult: imageResult,
                imageResultFuture: null,
                confirmedRegNumber: _confirmedRegNumber,
                isImageTrainedProduct: true,
              ),
            ),
          );
          _resetCaptureFlow(clearText: false);
        } else {
          await HistoryService.instance.addEntry(
            scannedText: raw,
            productInfo: null,
            status: 'NOT FOUND',
            imageInfo: imageResult.info,
            registrationStatus: RegistrationStatus.unregistered,
            imageStatus: imageResult.status,
            regNumber: _confirmedRegNumber,
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

  @override
  void dispose() {
    _stopStream();
    _textRecognizer.close();
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
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Checking for FDA updates?')),
                  );
                  await widget.fdaChecker.ensureLoadedAndFresh();
                  if (!mounted) return;
                  setState(() {});
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Update check complete')),
                  );
                },
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
                                const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'How scanning works',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(
                                    () => _showCaptureGuide = false,
                                  ),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const _GuideStep(
                              number: '1',
                              title: 'Capture the packaging (optional)',
                              body:
                                  'Take a clear photo of the label if your product is in our trained references so the app can compare colors, logos, and seals.',
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
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => setState(
                                  () => _showCaptureGuide = false,
                                ),
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
    final bool isPackaging = _activeCaptureStep == _CaptureStep.packaging;
    final bool captured = isPackaging ? _wideShotCaptured : _regShotCaptured;
    final bool skipped =
        isPackaging ? _packageCaptureSkipped : _regCaptureSkipped;
    final bool disabled = _isCapturing || _isMatching;
    final bool isConfirmStage = _canConfirmFlow;
    final bool confirmEnabled = isConfirmStage && !disabled;
    final Color textColor = Colors.white;
    final Color muted = Colors.white70;

    final IconData captureIcon =
        isPackaging ? Icons.camera_alt_rounded : Icons.document_scanner_rounded;
    final bool confirmMode = isConfirmStage;
    final IconData mainIcon = confirmMode
        ? Icons.check_rounded
        : (captured ? Icons.refresh_rounded : captureIcon);
    final String mainLabel = confirmMode
        ? (_isMatching ? 'Matching...' : 'Confirm scan')
        : (captured
            ? (isPackaging ? 'Retake packaging' : 'Retake reg number')
            : (isPackaging ? 'Capture packaging' : 'Capture reg number'));
    final VoidCallback? mainAction = confirmMode
        ? (confirmEnabled ? _confirmScan : null)
        : (disabled
            ? null
            : (isPackaging ? _startPackagingCapture : _startRegCapture));

    final IconData skipIcon =
        skipped ? Icons.undo_rounded : Icons.visibility_off_rounded;
    final String skipLabel = skipped
        ? (isPackaging ? 'Use packaging capture' : 'Add reg capture')
        : (isPackaging ? 'Skip packaging' : 'Skip reg capture');
    final VoidCallback? skipAction = disabled
        ? null
        : (isPackaging
            ? (skipped ? _resumePackagingCapture : _skipPackagingCapture)
            : (skipped ? _resumeRegCapture : _skipRegCapture));

    final VoidCallback? stepToggle = disabled
        ? null
        : () {
            setState(() {
              final nextStep = isPackaging
                  ? _CaptureStep.regNumber
                  : _CaptureStep.packaging;
              _activeCaptureStep = nextStep;
              if (nextStep == _CaptureStep.regNumber) {
                _pendingRegCapture = !_regShotCaptured;
              } else {
                _pendingRegCapture = false;
              }
            });
          };

    final String stepTitle = confirmMode
        ? 'Step 3 - Confirm'
        : (isPackaging ? 'Step 1 - Packaging' : 'Step 2 - Registration');
    final String statusText = confirmMode
        ? (_isMatching ? 'Matching in progress' : 'Ready to submit')
        : (skipped
            ? (isPackaging
                ? 'Skipped (uses packaging photo only)'
                : 'Skipped (uses packaging text)')
            : (captured ? 'Capture saved' : 'Ready to capture'));

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stepTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: RawMaterialButton(
                    onPressed: disabled ? null : mainAction,
                    fillColor: Colors.white.withValues(alpha: 0.95),
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: Icon(
                      mainIcon,
                      size: 28,
                      color:
                          isConfirmStage ? Colors.green : theme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mainLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _OverlayActionChip(
                      icon: skipIcon,
                      label: skipLabel,
                      onPressed: skipAction,
                    ),
                    _OverlayActionChip(
                      icon: Icons.swap_horiz_rounded,
                      label: isPackaging ? 'Go to Step 2' : 'Back to Step 1',
                      onPressed: stepToggle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
              Text(
                body,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverlayActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _OverlayActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: enabled ? Colors.white : Colors.white60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
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
              'Matching product?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
















