import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:basta_fda/models/scan_verdict.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';
import 'package:basta_fda/screens/not_found_screen.dart';
import 'package:basta_fda/screens/history_screen.dart';
import 'package:basta_fda/screens/settings_screen.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:basta_fda/services/mock_image_classifier.dart';
import 'package:basta_fda/services/settings_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  // Removed _streaming flag (was unused)
  bool _isBusy = false;
  bool _isMatching = false;
  final bool _paused = false;
  bool _torchOn = false;
  bool _liveMode = false; // Lens-like live OCR (off by default)
  String _extractedText = "";
  List<String> _suggestions = [];
  Size? _imageSize;
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  Timer? _debounce;
  bool _isCapturing = false;
  bool _showExtractedExpanded = false;
  String? _lastRawText; // keep last raw OCR text for Reg No extraction
  // Multi-angle capture session (accumulate OCR from multiple sides)
  final List<String> _sessionTexts = [];
  final List<String> _sessionRawTexts = [];
  bool _scopeNoticeShown = false;
  // Nudge throttling
  DateTime? _lastNudgeAt;
  // Tap-to-focus + pinch-to-zoom
  Offset? _lastFocusTap;
  DateTime? _lastFocusAt;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoomForScale = 1.0;
  final MockImageClassifier _imageClassifier =
      MockImageClassifier.instance;
  String? _confirmedRegNumber;

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

  Future<void> _startStream() async {
    if (!mounted ||
        _controller == null ||
        _controller!.value.isStreamingImages) {
      return;
    }
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

    _imageSize ??= Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation =
          InputImageRotationValue.fromRawValue(
            _controller!.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(cameraImage.format.raw) ??
          InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: imageRotation,
          format: format,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );

      final RecognizedText result = await _textRecognizer.processImage(
        inputImage,
      );
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
      // Suggest adding another side if OCR looks incomplete and setting is enabled
      _maybeNudgeAddSide(rawText, scannedText);
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
        try {
          await _controller!.unlockCaptureOrientation();
        } catch (_) {}
      }
    }
  }

  bool _shouldNudgeForAnotherSide(String raw, String clean) {
    // If a reg-like code is present, we already have strong evidence
    final hasReg = widget.fdaChecker.regCandidates(raw).isNotEmpty;
    if (hasReg) return false;

    final rawL = raw.toLowerCase();
    final cleanL = clean.toLowerCase();

    // Evidence cues
    final hasStrength =
        RegExp(r"\b\d+(?:\.\d+)?\s*(mg|g|mcg)\b").hasMatch(rawL) ||
        cleanL.contains('mg');
    final hasForm = [
      'tablet',
      'capsule',
      'syrup',
      'cream',
      'ointment',
      'solution',
      'suspension',
      'injection',
    ].any((t) => cleanL.contains(t));
    final hasParty =
        rawL.contains('manufactured by') ||
        rawL.contains('manufacturer') ||
        rawL.contains('distributed by') ||
        rawL.contains('distributor');
    final hasExpiryCue =
        rawL.contains('exp') ||
        rawL.contains('expiry') ||
        rawL.contains('expiration');

    int cues = 0;
    if (hasStrength) cues++;
    if (hasForm) cues++;
    if (hasParty) cues++;
    if (hasExpiryCue) cues++;

    // Very short text likely incomplete
    final tooShort = cleanL.length < 30;

    // Nudge when there is low evidence
    return cues < 2 || tooShort;
  }

  void _maybeNudgeAddSide(String raw, String clean) {
    final s = SettingsService.instance;
    if (!s.smartAddSidePrompt) return;
    if (!_shouldNudgeForAnotherSide(raw, clean)) return;
    final now = DateTime.now();
    if (_lastNudgeAt != null &&
        now.difference(_lastNudgeAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastNudgeAt = now;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Want better results? Save this side and scan another?',
        ),
        action: SnackBarAction(
          label: 'Save side',
          onPressed: () {
            final cleanTxt = _extractedText.trim();
            final rawTxt = (_lastRawText ?? _extractedText).trim();
            if (cleanTxt.isNotEmpty) _sessionTexts.add(cleanTxt);
            if (rawTxt.isNotEmpty) _sessionRawTexts.add(rawTxt);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Side saved (${_sessionRawTexts.length})'),
                ),
              );
            }
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  List<String> _extractSuggestions(RecognizedText result) {
    final List<String> collect = [];
    final imgW = _imageSize?.width ?? 1;
    final imgH = _imageSize?.height ?? 1;
    final roi = Rect.fromLTWH(
      imgW * 0.2,
      imgH * 0.325,
      imgW * 0.6,
      imgH * 0.35,
    );
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
        await _executeSearch(text, skipImageCheck: false);
      }
      return;
    }
    await _reviewAndSearch();
  }

  Future<void> _reviewAndSearch({
    String? preset,
    bool capturePhoto = true,
    bool allowImageCheck = true,
  }) async {
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
        final bool imageAllowed = allowImageCheck;
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const header = Text(
                        'Choose Registration Number',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                      if (regCandidates.isEmpty) {
                        return header;
                      }
                      final manualButton = FilledButton.tonalIcon(
                        onPressed: () async {
                          final selected = await showDialog<String>(
                            context: context,
                            builder: (dialogCtx) {
                              final manualController =
                                  TextEditingController(text: working);
                              return AlertDialog(
                                title: const Text('Enter registration number'),
                                content: TextField(
                                  controller: manualController,
                                  decoration: const InputDecoration(
                                    hintText: 'Type registration number here',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogCtx).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(dialogCtx)
                                        .pop(manualController.text.trim()),
                                    child: const Text('Use'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (selected != null && selected.isNotEmpty) {
                            if (!context.mounted) return;
                            Navigator.of(ctx).pop();
                            await _executeSearch(
                              selected,
                              rawOverride: selected,
                              skipImageCheck: !imageAllowed,
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Manual entry'),
                      );
                      if (constraints.maxWidth < 360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: manualButton,
                            ),
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          header,
                          manualButton,
                        ],
                      );
                    },
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
                    if (_sessionRawTexts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _sessionRawTexts.asMap().entries.map((
                              entry,
                            ) {
                              final idx = entry.key + 1;
                              final sample = entry.value.trim();
                              final preview = sample.length > 24
                                  ? "${sample.substring(0, 24)}..."
                                  : sample;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text("Side $idx - $preview"),
                                  deleteIcon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  onDeleted: () {
                                    setState(() {
                                      _sessionRawTexts.removeAt(idx - 1);
                                      if (idx - 1 < _sessionTexts.length) {
                                        _sessionTexts.removeAt(idx - 1);
                                      }
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
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
                      'No clear registration number detected.\nYou can enter it manually.',
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
    String? followUpText;
    Future<void> Function()? followUpAction;
    bool dialogShown = false;

    Future<ImageCheckResult> resolveImageCheck(String rawText) {
      if (skipImageCheck) {
        return Future.value(
          const ImageCheckResult(status: ImageCheckStatus.skipped),
        );
      }
      try {
        return _imageClassifier
            .classify(rawText: rawText, additionalText: text)
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

      final imageResultFuture = resolveImageCheck(raw);
      final initialImageResult = skipImageCheck
          ? const ImageCheckResult(status: ImageCheckStatus.skipped)
          : const ImageCheckResult(status: ImageCheckStatus.pending);

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

      if (matchedProduct != null) {
        final nonNullProduct = Map<String, String>.from(matchedProduct);
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
            );
          }),
        );

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanResultScreen(
              productInfo: nonNullProduct,
              status: status,
              registrationStatus: registrationStatus,
              initialImageResult: initialImageResult,
              imageResultFuture: imageResultFuture,
              confirmedRegNumber: _confirmedRegNumber,
            ),
          ),
        );
        _sessionTexts.clear();
        _sessionRawTexts.clear();
      } else {
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.of(context).pop();
          dialogShown = false;
          await Future<void>.delayed(Duration.zero);
        }
        final imageResult = await imageResultFuture;
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
        final returned = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NotFoundScreen(
              scannedText: raw,
              fdaChecker: widget.fdaChecker,
              imageInfo: imageResult.info,
              imageStatus: imageResult.status,
            ),
          ),
        );
        if (!mounted) return;
        if (returned is String && returned.isNotEmpty) {
          setState(() => _extractedText = returned);
          final wantsReview = SettingsService.instance.reviewBeforeSearch;
          if (wantsReview) {
            followUpAction = () => _reviewAndSearch(
                  preset: returned,
                  capturePhoto: false,
                  allowImageCheck: false,
                );
          } else {
            followUpText = returned;
          }
        }
      }
    } finally {
      if (mounted && dialogShown && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      _isMatching = false;
    }

    if (followUpAction != null) {
      await followUpAction();
    } else if (followUpText != null) {
      await _executeSearch(
        followUpText,
        skipImageCheck: true,
      );
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

          Positioned(
            left: 0,
            right: 0,
            bottom: 160,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Keep the registration text inside the frame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
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
                      'Loading FDA data…',
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
                    const SnackBar(content: Text('Checking for FDA updates…')),
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
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.92),
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black26),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Keep the label text inside the frame. We match it to FDA records, but you should still inspect for tampering.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  // Extracted text viewer (cleaned), with copy and expand controls
                  if (_extractedText.isNotEmpty) ...[
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Extracted Text',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Copy',
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: _extractedText),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Extracted text copied',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    _showExtractedExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 20,
                                  ),
                                  tooltip: _showExtractedExpanded
                                      ? 'Collapse'
                                      : 'Expand',
                                  onPressed: () => setState(
                                    () => _showExtractedExpanded =
                                        !_showExtractedExpanded,
                                  ),
                                ),
                              ],
                            ),
                            AnimatedCrossFade(
                              crossFadeState: _showExtractedExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 180),
                              firstChild: Text(
                                _extractedText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              secondChild: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 120,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    _extractedText,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
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
                            _extractedText = (_extractedText.isEmpty
                                ? t
                                : '$_extractedText $t');
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 10),
                  if (widget.fdaChecker.isLoaded) ...[
                    Text(
                      'Need another angle? Capture again for stronger OCR.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                        label: const Text('Add another angle'),
                        onPressed: _isCapturing
                            ? null
                            : () async {
                                final clean = _extractedText.trim();
                                final raw =
                                    (_lastRawText ?? _extractedText).trim();
                                if (clean.isNotEmpty) _sessionTexts.add(clean);
                                if (raw.isNotEmpty) _sessionRawTexts.add(raw);
                                final savedCount = _sessionRawTexts.length;
                                final scanned = await _scanFromPhoto();
                                if (!context.mounted) return;
                                if (scanned != null && scanned.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Angle $savedCount saved. New capture ready – add more or confirm.',
                                      ),
                                    ),
                                  );
                                } else if (savedCount > 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Angle $savedCount saved, but new capture was unclear. Try again.',
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                    if (_sessionRawTexts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Saved angles: ${_sessionRawTexts.length} (auto-applied on Confirm).',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                              ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isCapturing || !widget.fdaChecker.isLoaded
                          ? null
                          : () {
                              if (_sessionRawTexts.isNotEmpty ||
                                  _sessionTexts.isNotEmpty) {
                                final combinedRaw =
                                    ([..._sessionRawTexts, _lastRawText ?? '']
                                            .where((s) => s.trim().isNotEmpty)
                                            .join(' '))
                                        .trim();
                                final combinedClean =
                                    ([..._sessionTexts, _extractedText]
                                            .where((s) => s.trim().isNotEmpty)
                                            .join(' '))
                                        .trim();
                                final wantsReview =
                                    SettingsService.instance.reviewBeforeSearch;
                                if (wantsReview) {
                                  _reviewAndSearch(
                                    preset: combinedClean,
                                    capturePhoto: false,
                                    allowImageCheck: true,
                                  );
                                } else {
                                  _executeSearch(
                                    combinedClean,
                                    rawOverride: combinedRaw,
                                    skipImageCheck: false,
                                  );
                                }
                              } else {
                                _matchScannedText();
                              }
                            },
                      child: _isCapturing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.fdaChecker.isLoaded
                                  ? 'Confirm'
                                  : 'Loading...',
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.drive_file_rename_outline_rounded),
                      label: const Text('Enter registration manually'),
                      onPressed: _isCapturing
                          ? null
                          : () {
                              _reviewAndSearch(
                                preset: '',
                                capturePhoto: false,
                                allowImageCheck: false,
                              );
                            },
                    ),
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
              'Matching product…',
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




