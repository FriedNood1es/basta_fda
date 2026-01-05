import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:share_plus/share_plus.dart';

import 'package:image_picker/image_picker.dart';

import 'package:basta_fda/services/settings_service.dart';
import 'package:basta_fda/models/scan_verdict.dart';

class ScanResultScreen extends StatefulWidget {
  static const viewHistoryResult = 'view_history';
  static const scanAgainResult = 'scan_again';
  final Map<String, String> productInfo;
  final String status;
  final RegistrationStatus registrationStatus;
  final ImageCheckResult initialImageResult;
  final Future<ImageCheckResult>? imageResultFuture;
  final String? confirmedRegNumber;
  final String? packagingImagePath;

  const ScanResultScreen({
    super.key,
    required this.productInfo,
    required this.status,
    required this.registrationStatus,
    required this.initialImageResult,
    this.imageResultFuture,
    this.confirmedRegNumber,
    this.packagingImagePath,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  late ImageCheckResult _imageResult;
  bool _alertShown = false;
  static const Set<String> _missingValueTokens = {
    '',
    'n/a',
    'na',
    'none',
    'not applicable',
    'null',
  };

  @override
  void initState() {
    super.initState();
    _imageResult = widget.initialImageResult;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowSuspiciousAlert(),
    );
    widget.imageResultFuture?.then((result) {
      if (!mounted || result == _imageResult) return;
      setState(() => _imageResult = result);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowSuspiciousAlert(),
      );
    });
  }

  Map<String, double> _imageConfidenceBreakdown() {
    final info = _imageResult.info;
    if (info == null || info.isEmpty) return const {};
    double parseScore(String key) {
      final raw = info[key];
      if (raw == null) return 0;
      final value = double.tryParse(raw);
      if (value == null || value.isNaN) return 0;
      return value;
    }

    double authentic = parseScore('authenticScore');
    if (authentic <= 0) {
      authentic = parseScore('confidence');
    }
    double suspicious = parseScore('suspiciousScore');
    if (authentic > 0 && suspicious <= 0) {
      suspicious = (1 - authentic).clamp(0.0, 1.0).toDouble();
    } else if (suspicious > 0 && authentic <= 0) {
      authentic = (1 - suspicious).clamp(0.0, 1.0).toDouble();
    }
    if (authentic <= 0 && suspicious <= 0) return const {};
    double clamp(double v) => v.clamp(0.0, 1.0).toDouble();
    return {'authentic': clamp(authentic), 'suspicious': clamp(suspicious)};
  }

  void _maybeShowSuspiciousAlert() {
    if (!mounted || _alertShown || _imageResult.info == null) {
      return;
    }
    final breakdown = _imageConfidenceBreakdown();
    if (breakdown.isEmpty) return;
    final suspicious = breakdown['suspicious'] ?? 0;
    final authentic = breakdown['authentic'] ?? 0;
    if (suspicious <= authentic) return;
    _alertShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.error,
                      theme.colorScheme.error.withAlpha(215),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Packaging alert',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Suspicious cues are stronger than authentic cues. Pause and inspect the pack before logging it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AlertBullet(
                      icon: Icons.verified_outlined,
                      text:
                          'Compare colors, fonts, and seals with a trusted product photo.',
                    ),
                    _AlertBullet(
                      icon: Icons.fact_check_rounded,
                      text:
                          'If you bought this recently, check the receipt or supplier for red flags.',
                    ),
                    _AlertBullet(
                      icon: Icons.report_problem_outlined,
                      text:
                          'Report the pack if tampering, spelling mistakes, or stickered dates are present.',
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 24,
                thickness: 1,
                indent: 20,
                endIndent: 20,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showRedFlagsChecklist(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Review red flags'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Inspect packaging'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _titleCase(String? s) {
    if (s == null || s.isEmpty) return 'N/A';
    return s
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')),
        )
        .join(' ');
  }

  bool _isPlaceholderValue(String? raw) {
    if (raw == null) return true;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    return _missingValueTokens.contains(trimmed.toLowerCase());
  }

  String _brandDisplayName(Map<String, String> info, {bool includeNote = true}) {
    final brand = info['brand_name'];
    if (!_isPlaceholderValue(brand)) return _titleCase(brand);
    final generic = info['generic_name'];
    if (!_isPlaceholderValue(generic)) {
      final genericLabel = _titleCase(generic);
      return includeNote ? '$genericLabel (brand not listed)' : genericLabel;
    }
    return 'Brand not listed';
  }

  bool _packagingFileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyRegNumber(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Registration number copied')));
  }

  Future<void> _shareScanSummary() async {
    final info = widget.productInfo;
    final buffer = StringBuffer()
      ..writeln('bastaFDA scan summary')
      ..writeln('')
      ..writeln('Registration status: ${widget.registrationStatus.label}')
      ..writeln('Scan status: ${widget.status}');
    final brand = _brandDisplayName(info);
    if (brand != 'N/A') buffer.writeln('Brand: $brand');
    final generic = _titleCase(info['generic_name']);
    if (generic != 'N/A') buffer.writeln('Generic: $generic');
    final manufacturer = _titleCase(info['manufacturer']);
    if (manufacturer != 'N/A') buffer.writeln('Manufacturer: $manufacturer');
    final regNumber = (() {
      final confirmed = widget.confirmedRegNumber?.trim();
      if (confirmed != null && confirmed.isNotEmpty) return confirmed;
      final fromProduct = info['reg_no']?.trim();
      if (fromProduct != null && fromProduct.isNotEmpty) return fromProduct;
      return null;
    })();
    if (regNumber != null) buffer.writeln('Registration number: $regNumber');
    final imageInfo = _imageResult.info;
    buffer.writeln('Image helper status: ${_imageResult.status.label}');
    if (imageInfo != null) {
      final verdict = imageInfo['verdict'];
      final confidence = imageInfo['confidence'];
      final product = imageInfo['product'];
      if (product != null && product.isNotEmpty) {
        buffer.writeln('Packaging match: $product');
      }
      if (verdict != null && verdict.isNotEmpty) {
        buffer.writeln('Image verdict: ${_titleCase(verdict)}');
      }
      if (confidence != null && confidence.isNotEmpty) {
        buffer.writeln('Image confidence: $confidence');
      }
    }
    buffer.writeln(
      'Packaging photo: ${_packagingFileExists(widget.packagingImagePath) ? 'Captured' : 'Not provided'}',
    );
    await Share.share(
      buffer.toString().trim(),
      subject: 'bastaFDA scan result',
    );
  }

  Future<void> _showPackagingFullPreview(String path) async {
    if (!_packagingFileExists(path) || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: size.height * 0.7,
                child: InteractiveViewer(
                  minScale: 0.75,
                  maxScale: 4,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        'Unable to load photo',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRedFlagsChecklist(BuildContext context) {
    const redFlags = [
      'Seals or blister packs look broken, resealed, or tampered.',

      'Printing looks blurry, smudged, or colors look off compared to previous purchases.',

      'Spelling mistakes, inconsistent fonts, or missing regulatory markings.',

      'Expiry, batch, or manufacturing dates look altered, stickered over, or mismatched.',

      'Packaging quality feels flimsy or different from what you usually see.',
    ];

    showModalBottomSheet(
      context: context,

      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),

      builder: (ctx) {
        final theme = Theme.of(ctx);

        final bottom = MediaQuery.of(ctx).viewInsets.bottom;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 20),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,

                      color: theme.colorScheme.primary,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Visual Red Flags Checklist',

                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),

                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                for (final item in redFlags)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),

                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const Icon(
                          Icons.check_box_outline_blank_rounded,

                          size: 20,

                          color: Colors.redAccent,
                        ),

                        const SizedBox(width: 12),

                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                Text(
                  'If any of these red flags show up, submit a report so our team or the FDA can review the packaging.',

                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,

                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),

                    icon: const Icon(Icons.check_rounded),

                    label: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String niceDate(String? s) => _titleCase(s);

    Color statusColor(String status, ThemeData theme) {
      switch (status.toUpperCase()) {
        case 'RECOGNIZED':
          return Colors.green.shade600;

        case 'EXPIRED':
          return Colors.orange.shade700;

        case 'UNRECOGNIZED':
          return theme.colorScheme.error;

        case 'NOT FOUND':
          return theme.colorScheme.error;

        default:
          return theme.colorScheme.primary;
      }
    }

    final productInfo = widget.productInfo;
    final bool missingBrand = _isPlaceholderValue(productInfo['brand_name']);
    final status = widget.status;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    String registrationStatusNote(RegistrationStatus status) {
      switch (status) {
        case RegistrationStatus.registered:
          return '“Registered” means we matched this scan to an FDA record in our database.';
        case RegistrationStatus.unregistered:
          return '“Unregistered” means no matching FDA record was found for the scanned details.';
        case RegistrationStatus.skipped:
          return '“Skipped” means no registration number was provided; rely on packaging cues for verification.';
      }
    }

    String? packagingStatusNote(RegistrationStatus status) {
      if (status == RegistrationStatus.skipped) {
        return 'Packaging helper is the primary check for categories without FDA codes. Inspect the pack carefully before trusting it.';
      }
      return 'Packaging helper is a visual aid; the FDA registration match remains the primary verification.';
    }

    Widget verdictInfoRow({
      required IconData icon,
      required Color color,
      required String title,
      required String body,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final imageInfo = _imageResult.info;
    final imageVerdict = imageInfo?['verdict'] ?? '';
    final confirmedRegRaw = widget.confirmedRegNumber?.trim();
    final fallbackRegRaw = productInfo['reg_no']?.trim();
    final copyableRegNumber =
        (confirmedRegRaw != null && confirmedRegRaw.isNotEmpty)
        ? confirmedRegRaw
        : (fallbackRegRaw != null && fallbackRegRaw.isNotEmpty
              ? fallbackRegRaw
              : null);
    final regNoLabel = copyableRegNumber?.toUpperCase() ?? 'N/A';
    final sColor = statusColor(status, theme);
    final Color registrationColor;
    switch (widget.registrationStatus) {
      case RegistrationStatus.registered:
        registrationColor = Colors.green.shade600;
        break;
      case RegistrationStatus.unregistered:
        registrationColor = theme.colorScheme.error;
        break;
      case RegistrationStatus.skipped:
        registrationColor = theme.colorScheme.outline;
        break;
    }
    final imageChipValue = imageVerdict == 'suspicious'
        ? 'Suspicious'
        : _imageResult.status.label;
    Color imageColor;
    if (imageVerdict == 'suspicious') {
      imageColor = theme.colorScheme.error;
    } else {
      switch (_imageResult.status) {
        case ImageCheckStatus.recognized:
          imageColor = theme.colorScheme.primary;
          break;
        case ImageCheckStatus.unrecognized:
          imageColor = theme.colorScheme.tertiary;
          break;
        case ImageCheckStatus.failed:
          imageColor = theme.colorScheme.error;
          break;
        case ImageCheckStatus.skipped:
        case ImageCheckStatus.pending:
          imageColor = theme.colorScheme.outline;
          break;
      }
    }
    final imageProduct = imageInfo?['product'] ?? '';
    final imageCategory = imageInfo?['category'] ?? '';
    final imageConfidence = imageInfo?['confidence'] ?? '';
    final imageSource = imageInfo?['source'] ?? '';
    final matchReason = (productInfo['match_reason'] ?? '').toString().trim();
    final verificationReason = (productInfo['verification_reasons'] ?? '')
        .toString()
        .trim();
    final bool showVerdictCard =
        matchReason.isNotEmpty || verificationReason.isNotEmpty;
    final verdictLabel = imageVerdict.isNotEmpty
        ? _titleCase(imageVerdict)
        : _imageResult.status.label;
    final String? packagingPath = widget.packagingImagePath;
    final hasPackagingPhoto = _packagingFileExists(packagingPath);
    final Widget? packagingPreview = hasPackagingPhoto && packagingPath != null
        ? _PackagingPreviewCard(
            path: packagingPath,
            onTap: () => _showPackagingFullPreview(packagingPath),
          )
        : null;

    final Widget? packagingSection = () {
      final breakdown = _imageConfidenceBreakdown();
      if (breakdown.isNotEmpty) {
        return _PackagingConfidenceCard(
          authenticScore: breakdown['authentic'] ?? 0,
          suspiciousScore: breakdown['suspicious'] ?? 0,
          productName: _brandDisplayName(productInfo, includeNote: false),
        );
      }

      switch (_imageResult.status) {
        case ImageCheckStatus.pending:
          return const _InfoBanner(
            icon: Icons.hourglass_top_rounded,
            title: 'Packaging check in progress',
            message:
                'We are comparing your photo to our reference images. Results will appear shortly.',
          );
        case ImageCheckStatus.skipped:
          return const _InfoBanner(
            icon: Icons.image_not_supported_rounded,
            title: 'Packaging check unavailable',
            message:
                'This scan did not include a usable packaging photo. Verification relies on the registration number.',
          );
        case ImageCheckStatus.failed:
          return const _InfoBanner(
            icon: Icons.error_outline_rounded,
            title: 'Packaging check failed',
            message:
                'Something went wrong while running the packaging helper. Retake the photo and try again.',
          );
        case ImageCheckStatus.unrecognized:
          return const _InfoBanner(
            icon: Icons.help_outline_rounded,
            title: 'Packaging not recognized',
            message:
                'We could not match the packaging photo to our reference models yet.',
          );
        case ImageCheckStatus.recognized:
          return null;
      }
    }();

    final bool hasPackagingDetails =
        packagingSection != null &&
        (imageProduct.isNotEmpty ||
            imageCategory.isNotEmpty ||
            imageConfidence.isNotEmpty ||
            imageSource.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Result')),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            const _SectionHeader(label: 'Match summary'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.07),

                borderRadius: BorderRadius.circular(16),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: primary.withValues(alpha: 0.1),
                        child: Image.asset('assets/logo.png', height: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _brandDisplayName(productInfo),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Registration No.: $regNoLabel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Last Updated: ${niceDate(productInfo['issuance_date'])}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        title: 'Registration',
                        value: widget.registrationStatus.label,
                        color: registrationColor,
                        icon: Icons.rule_folder_rounded,
                      ),
                      _StatusChip(
                        title: 'Image',
                        value: imageChipValue,
                        color: imageColor,
                        icon: Icons.image_search_rounded,
                      ),
                      if (copyableRegNumber != null)
                        _RegNumberChip(
                          regNumber: copyableRegNumber.toUpperCase(),
                          onCopy: () => _copyRegNumber(copyableRegNumber),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registrationStatusNote(widget.registrationStatus),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    packagingStatusNote(widget.registrationStatus) ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            if (missingBrand) ...[
              const SizedBox(height: 12),
              const _InfoBanner(
                icon: Icons.info_outline_rounded,
                title: 'Brand not listed in FDA record',
                message:
                    'Only the generic name is provided for this registration. Please rely on the reg. number when verifying.',
              ),
            ],

            if (packagingPreview != null || packagingSection != null) ...[
              const SizedBox(height: 20),
              const _SectionHeader(label: 'Packaging review'),
              const SizedBox(height: 8),
              if (packagingPreview != null) packagingPreview,
              if (packagingPreview != null && packagingSection != null)
                const SizedBox(height: 12),
              if (packagingSection != null) packagingSection,
            ],

            if (hasPackagingDetails) ...[
              const SizedBox(height: 12),
              const _SectionHeader(label: 'Packaging helper details'),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.image_search_rounded),
                  title: Text(
                    imageProduct.isNotEmpty
                        ? imageProduct
                        : 'Image model preview',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageVerdict.isNotEmpty)
                        Text('Verdict: ${_titleCase(imageVerdict)}'),
                      if (imageCategory.isNotEmpty)
                        Text('Category: ${_titleCase(imageCategory)}'),
                      if (imageConfidence.isNotEmpty)
                        Text('Confidence: $imageConfidence'),
                      if (imageSource.isNotEmpty) Text('Source: $imageSource'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_imageResult.status.needsWarning) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Registration verification relied on text only. Capture a reference image when possible.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            const _SectionHeader(label: 'Share scan'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _shareScanSummary,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share scan'),
              ),
            ),

            const SizedBox(height: 16),

            const _SectionHeader(label: 'Product details'),
            const SizedBox(height: 8),
            // Details card
            Card(
              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),

              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),

                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.label_rounded,
                      label: 'Brand Name',
                      value: _brandDisplayName(productInfo),
                    ),

                    _DetailRow(
                      icon: Icons.science_rounded,

                      label: 'Generic Name',

                      value: _titleCase(productInfo['generic_name']),
                    ),

                    _DetailRow(
                      icon: Icons.category_rounded,

                      label: 'Category',

                      value: _titleCase(productInfo['category']),
                    ),

                    _DetailRow(
                      icon: Icons.speed_rounded,

                      label: 'Dosage Strength',

                      value: productInfo['dosage_strength'] ?? 'N/A',
                    ),

                    _DetailRow(
                      icon: Icons.medication_rounded,

                      label: 'Dosage Form',

                      value: _titleCase(productInfo['dosage_form']),
                    ),

                    _DetailRow(
                      icon: Icons.factory_rounded,

                      label: 'Manufacturer',

                      value: _titleCase(productInfo['manufacturer']),
                    ),

                    _DetailRow(
                      icon: Icons.public_rounded,

                      label: 'Country',

                      value: _titleCase(productInfo['country']),
                    ),

                    _DetailRow(
                      icon: Icons.local_shipping_rounded,

                      label: 'Distributor',

                      value: _titleCase(productInfo['distributor']),

                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ),

            if (showVerdictCard && !hasPackagingDetails) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            imageVerdict == 'suspicious'
                                ? Icons.warning_rounded
                                : Icons.verified_rounded,
                            color: imageColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scan verdict',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Image verdict: $verdictLabel | Registration: ${widget.registrationStatus.label}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (matchReason.isNotEmpty)
                        verdictInfoRow(
                          icon: Icons.task_alt_rounded,
                          color: theme.colorScheme.primary,
                          title: 'Why this matched',
                          body: matchReason,
                        ),
                      if (verificationReason.isNotEmpty)
                        verdictInfoRow(
                          icon: Icons.warning_amber_rounded,
                          color: sColor,
                          title: 'Why this status',
                          body: verificationReason,
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            const _SectionHeader(label: 'Visual checks'),
            const SizedBox(height: 8),
            // Visual safety checks
            Card(
              margin: const EdgeInsets.only(top: 20),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),

              child: ListTile(
                leading: Icon(
                  Icons.visibility_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Visual Red Flags'),
                subtitle: const Text(
                  'Does the packaging look tampered, blurry, or poorly printed? Tap to review the quick checklist.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showRedFlagsChecklist(context),
              ),
            ),

            Container(
              margin: const EdgeInsets.only(top: 24),

              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),

              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),

                borderRadius: BorderRadius.circular(12),

                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Icon(
                    Icons.info_outline_rounded,

                    color: theme.colorScheme.primary,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      'We only match this label to FDA registration records. Packaging authenticity still needs your judgment - please report anything that looks tampered.',

                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const _SectionHeader(label: 'Take action'),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        builder: (ctx) => _ReportProductSheet(
                          productInfo: productInfo,
                          status: status,
                          registrationStatus: widget.registrationStatus,
                          imageStatus: _imageResult.status,
                          imageInfo: _imageResult.info,
                          confirmedRegNumber: widget.confirmedRegNumber,
                        ),
                      );
                    },
                    icon: const Icon(Icons.report_gmailerrorred_rounded),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: const Text('Report Suspicious Product'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop(ScanResultScreen.scanAgainResult),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan another product'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: theme.colorScheme.outline),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(ScanResultScreen.viewHistoryResult),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('View scan history'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PackagingPreviewCard extends StatelessWidget {
  final String path;
  final VoidCallback onTap;

  const _PackagingPreviewCard({required this.path, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Text('Preview unavailable'),
              ),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              'Captured packaging photo',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text('Tap to zoom and inspect tampering cues.'),
            trailing: Icon(
              Icons.fullscreen_rounded,
              color: theme.colorScheme.primary,
            ),
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _PackagingConfidenceCard extends StatelessWidget {
  final double authenticScore;
  final double suspiciousScore;
  final String productName;

  const _PackagingConfidenceCard({
    required this.authenticScore,
    required this.suspiciousScore,
    required this.productName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final _ConfidenceDescriptor descriptor = _ConfidenceDescriptor.fromScore(
      authenticScore,
      theme,
    );
    final indicators = List<Widget>.generate(3, (index) {
      final filled = index < descriptor.level;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: filled
              ? descriptor.color
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      );
    });

    final bool highlightSuspicious = suspiciousScore >= 0.35;
    final String note = highlightSuspicious
        ? 'Packaging helper noticed a few unfamiliar cues. Slow down and compare seals, fonts, and lot codes yourself.'
        : 'No strong suspicious cues surfaced in this capture. Still trust your instincts and inspect seals or labels if anything feels off.';

    final trimmedName = productName.trim();
    final String nameLabel = trimmedName.isEmpty || trimmedName == 'N/A'
        ? 'Packaging helper'
        : '$trimmedName packaging helper';

    Widget buildPoint(
      IconData icon,
      Color color,
      String text, {
      TextStyle? style,
    }) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: style ?? theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    final Widget statusChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: descriptor.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        descriptor.title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: descriptor.color,
        ),
      ),
    );

    final IconData advisoryIcon = highlightSuspicious
        ? Icons.report_problem_rounded
        : Icons.visibility_rounded;
    final Color advisoryColor = highlightSuspicious
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final TextStyle? guidanceStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_rounded, color: descriptor.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nameLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                statusChip,
                Row(mainAxisSize: MainAxisSize.min, children: indicators),
              ],
            ),
            buildPoint(
              Icons.verified_user_rounded,
              descriptor.color,
              descriptor.detail,
            ),
            buildPoint(
              advisoryIcon,
              advisoryColor,
              note,
              style: theme.textTheme.bodySmall,
            ),
            buildPoint(
              Icons.assignment_turned_in_rounded,
              theme.colorScheme.onSurfaceVariant,
              'Packaging helper guides you, but the FDA registration result is still the primary verdict.',
              style: guidanceStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceDescriptor {
  final int level;
  final String title;
  final String detail;
  final Color color;

  const _ConfidenceDescriptor({
    required this.level,
    required this.title,
    required this.detail,
    required this.color,
  });

  factory _ConfidenceDescriptor.fromScore(double score, ThemeData theme) {
    final normalized = score.clamp(0.0, 1.0).toDouble();
    if (normalized >= 0.75) {
      return _ConfidenceDescriptor(
        level: 3,
        title: '✔✔✔ Strong match',
        detail:
            'Model recognized multiple authentic cues that match our reference gallery.',
        color: Colors.green.shade600,
      );
    }
    if (normalized >= 0.45) {
      return _ConfidenceDescriptor(
        level: 2,
        title: '✔✔ Moderate match',
        detail:
            'Model saw some familiar details, but lighting or framing might need improvement.',
        color: Colors.yellow.shade600,
      );
    }
    if (normalized >= 0.2) {
      return _ConfidenceDescriptor(
        level: 1,
        title: '✔ Low match',
        detail:
            'Model struggled to recognize this capture. Retake a clearer wide shot before trusting the packaging.',
        color: Colors.orange.shade600,
      );
    }
    return _ConfidenceDescriptor(
      level: 0,
      title: '⚠ Critical match',
      detail:
          'Confidence is extremely low. Treat this as suspicious and rely on another verification step.',
      color: theme.colorScheme.error,
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(message),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

class _AlertBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AlertBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _RegNumberChip extends StatelessWidget {
  final String regNumber;
  final VoidCallback onCopy;

  const _RegNumberChip({required this.regNumber, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.numbers_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REGISTRATION NO.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.7,
                    color: theme.hintColor,
                  ),
                ),
                Text(
                  regNumber,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 16, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.7,
                  color: color,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;

  final String label;

  final String value;

  final bool showDivider;

  const _DetailRow({
    required this.icon,

    required this.label,

    required this.value,

    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        ListTile(
          dense: true,

          leading: Icon(icon, color: theme.colorScheme.primary),

          title: Text(
            label,

            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),

          subtitle: Text(value, style: theme.textTheme.bodyMedium),

          contentPadding: const EdgeInsets.symmetric(horizontal: 8),

          minLeadingWidth: 24,
        ),

        if (showDivider) const Divider(height: 0),
      ],
    );
  }
}

class _ReportProductSheet extends StatefulWidget {
  final Map<String, String> productInfo;

  final String status;

  final RegistrationStatus registrationStatus;
  final ImageCheckStatus imageStatus;
  final Map<String, String>? imageInfo;
  final String? confirmedRegNumber;

  const _ReportProductSheet({
    required this.productInfo,
    required this.status,
    required this.registrationStatus,
    required this.imageStatus,
    this.imageInfo,
    this.confirmedRegNumber,
  });

  @override
  State<_ReportProductSheet> createState() => _ReportProductSheetState();
}

class _ReportProductSheetState extends State<_ReportProductSheet> {
  final _formKey = GlobalKey<FormState>();

  final _descCtrl = TextEditingController();

  final _contactCtrl = TextEditingController();

  String _category = 'Counterfeit';

  bool _submitting = false;

  static const List<String> _adminEmails = [
    'safety@bastafda.com',
    'kentlozano45@gmail.com',
  ];

  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;

  String? _imageError;

  @override
  void initState() {
    super.initState();

    () async {
      await SettingsService.instance.load();

      final savedCat = SettingsService.instance.lastReportCategory;

      final savedContact = SettingsService.instance.lastReportContact;

      String initial = savedCat?.isNotEmpty == true ? savedCat! : _category;

      final s = widget.status.toUpperCase();

      if (savedCat == null || savedCat.isEmpty) {
        if (s == 'EXPIRED') {
          initial = 'Expired in market';
        } else if (s == 'UNRECOGNIZED') {
          initial = 'Counterfeit';
        }
      }

      if (mounted) {
        setState(() {
          _category = initial;

          if (savedContact != null && savedContact.isNotEmpty) {
            _contactCtrl.text = savedContact;
          }
        });
      }
    }();
  }

  @override
  void dispose() {
    _descCtrl.dispose();

    _contactCtrl.dispose();

    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_submitting) return;

    try {
      final picked = await _picker.pickImage(
        source: source,

        maxWidth: 1600,

        imageQuality: 85,
      );

      if (!mounted) return;

      setState(() {
        _selectedImage = picked;

        _imageError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _imageError =
            'Could not access the ${source == ImageSource.camera ? 'camera' : 'gallery'}.';
      });
    }
  }

  String _buildSummary() {
    final imageSummary =
        widget.imageInfo?['product'] ??
        widget.imageInfo?['verdict'] ??
        widget.imageStatus.label;
    final summary = StringBuffer()
      ..writeln('Suspicious Product Report')
      ..writeln('Admins: ${_adminEmails.join(', ')}')
      ..writeln('')
      ..writeln('Category: $_category')
      ..writeln('Description: ${_descCtrl.text.trim()}')
      ..writeln('Contact: ${_contactCtrl.text.trim()}')
      ..writeln('')
      ..writeln('Brand: ${widget.productInfo['brand_name'] ?? ''}')
      ..writeln('Generic: ${widget.productInfo['generic_name'] ?? ''}')
      ..writeln(
        'Confirmed Reg No: ${widget.confirmedRegNumber ?? widget.productInfo['reg_no'] ?? ''}',
      )
      ..writeln('Registration Status: ${widget.registrationStatus.label}')
      ..writeln('Image Check: $imageSummary')
      ..writeln(
        'Dosage: ${widget.productInfo['dosage_form'] ?? ''} ${widget.productInfo['dosage_strength'] ?? ''}',
      )
      ..writeln('Manufacturer: ${widget.productInfo['manufacturer'] ?? ''}')
      ..writeln('Distributor: ${widget.productInfo['distributor'] ?? ''}')
      ..writeln('Country: ${widget.productInfo['country'] ?? ''}');
    final conf = widget.imageInfo?['confidence'];
    if (conf != null && conf.isNotEmpty) {
      summary.writeln('Image Confidence: $conf');
    }
    return summary.toString();
  }

  void _removeImage() {
    if (_submitting) return;

    setState(() {
      _selectedImage = null;

      _imageError = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final user = FirebaseAuth.instance.currentUser;

      String? imageUrl;

      String? storagePath;

      if (_selectedImage != null) {
        try {
          final file = File(_selectedImage!.path);

          if (await file.exists()) {
            final stamp = DateTime.now().millisecondsSinceEpoch;

            final uid = user?.uid ?? 'anonymous';

            final ref = FirebaseStorage.instance.ref().child(
              'report_uploads/$uid/$stamp.jpg',
            );

            final metadata = SettableMetadata(contentType: 'image/jpeg');

            await ref.putFile(file, metadata);

            imageUrl = await ref.getDownloadURL();

            storagePath = ref.fullPath;
          } else {
            if (mounted) {
              setState(() => _selectedImage = null);
            }

            messenger.showSnackBar(
              const SnackBar(
                content: Text('Selected photo could not be found.'),
              ),
            );
          }
        } catch (e) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Could not upload photo. Report submitted without image.',
              ),
            ),
          );
        }
      }

      final data = <String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),

        'status': widget.status,

        'category': _category,

        'description': _descCtrl.text.trim(),

        'contact': _contactCtrl.text.trim(),

        'createdByUid': user?.uid ?? 'anonymous',

        'createdByEmail': user?.email ?? '',

        'reg_no': widget.productInfo['reg_no'] ?? '',

        'brand_name': widget.productInfo['brand_name'] ?? '',

        'generic_name': widget.productInfo['generic_name'] ?? '',

        'dosage_form': widget.productInfo['dosage_form'] ?? '',

        'dosage_strength': widget.productInfo['dosage_strength'] ?? '',

        'country': widget.productInfo['country'] ?? '',

        'manufacturer': widget.productInfo['manufacturer'] ?? '',

        'distributor': widget.productInfo['distributor'] ?? '',

        'registrationStatus': widget.registrationStatus.name,

        'imageStatus': widget.imageStatus.name,

        'confirmedRegNumber': widget.confirmedRegNumber ?? '',

        'reason':
            widget.productInfo['verification_reasons'] ??
            widget.productInfo['match_reason'] ??
            '',

        'appSource': 'scan_result_screen',

        'hasImage': imageUrl != null,
      };

      if (imageUrl != null) {
        data['imageUrl'] = imageUrl;

        if (storagePath != null) {
          data['imageStoragePath'] = storagePath;
        }
      }

      await FirebaseFirestore.instance.collection('reports').add(data);

      SettingsService.instance.lastReportCategory = _category;

      SettingsService.instance.lastReportContact = _contactCtrl.text.trim();

      await SettingsService.instance.save();

      if (mounted) Navigator.of(context).pop();

      messenger.showSnackBar(const SnackBar(content: Text('Report submitted')));
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not submit report. Configure Firebase.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),

      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

          child: Form(
            key: _formKey,

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.report_gmailerrorred_rounded,

                      color: Colors.redAccent,
                    ),

                    const SizedBox(width: 8),

                    const Text(
                      'Report Suspicious Product',

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const Spacer(),

                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),

                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  value: _category,

                  items: const [
                    DropdownMenuItem(
                      value: 'Counterfeit',

                      child: Text('Counterfeit'),
                    ),

                    DropdownMenuItem(
                      value: 'Tampered',

                      child: Text('Tampered'),
                    ),

                    DropdownMenuItem(
                      value: 'Expired in market',

                      child: Text('Expired in market'),
                    ),

                    DropdownMenuItem(
                      value: 'Adverse effect',

                      child: Text('Adverse effect'),
                    ),

                    DropdownMenuItem(
                      value: 'Incorrect label',

                      child: Text('Incorrect label'),
                    ),

                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],

                  onChanged: (v) => setState(() => _category = v ?? _category),

                  decoration: const InputDecoration(labelText: 'Category'),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _descCtrl,

                  maxLines: 3,

                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',

                    hintText:
                        'What seems suspicious? Where purchased? Any details?',
                  ),

                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please provide a short description'
                      : null,
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _contactCtrl,

                  decoration: const InputDecoration(
                    labelText: 'Contact (optional)',

                    hintText: 'Email or phone if you want follow-up',
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Packaging photo (optional)',

                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Attach a clear shot of the packaging so reviewers can inspect tampering or quality issues.',

                  style: theme.textTheme.bodySmall,
                ),

                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,

                  runSpacing: 8,

                  children: [
                    OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _pickImage(ImageSource.camera),

                      icon: const Icon(Icons.photo_camera_rounded),

                      label: const Text('Take photo'),
                    ),

                    OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => _pickImage(ImageSource.gallery),

                      icon: const Icon(Icons.photo_library_rounded),

                      label: const Text('Choose file'),
                    ),

                    if (_selectedImage != null)
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _removeImage,

                        icon: const Icon(Icons.delete_outline_rounded),

                        label: const Text('Remove photo'),
                      ),
                  ],
                ),

                if (_imageError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),

                    child: Text(
                      _imageError!,

                      style: TextStyle(
                        color: theme.colorScheme.error,

                        fontSize: 12,
                      ),
                    ),
                  ),

                if (_selectedImage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),

                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,

                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),

                            child: Image.file(
                              File(_selectedImage!.path),

                              fit: BoxFit.cover,

                              errorBuilder: (context, error, _) => Container(
                                color: Colors.black12,

                                alignment: Alignment.center,

                                child: const Text('Unable to load preview'),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          top: 8,

                          right: 8,

                          child: IconButton(
                            onPressed: _submitting ? null : _removeImage,

                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,

                              foregroundColor: Colors.white,

                              visualDensity: VisualDensity.compact,
                            ),

                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,

                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,

                    icon: _submitting
                        ? const SizedBox(
                            width: 16,

                            height: 16,

                            child: CircularProgressIndicator(
                              strokeWidth: 2,

                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),

                    label: Text(
                      _submitting ? 'Submitting...' : 'Submit Report',
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Share.share(
                            _buildSummary(),
                            subject: 'Suspicious Product Report',
                          );
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share report via...'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final subject = Uri.encodeComponent(
                            'Suspicious Product Report',
                          );
                          final body = Uri.encodeComponent(_buildSummary());
                          final mailto = _adminEmails
                              .map((e) => Uri.encodeComponent(e))
                              .join(',');
                          final uri =
                              'mailto:$mailto?subject=$subject&body=$body';
                          await Share.share(
                            uri,
                            subject: 'Send email to admin',
                          );
                        },
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Email to admin'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
