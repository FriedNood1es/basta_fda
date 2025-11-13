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
  final Map<String, String> productInfo;
  final String status;
  final RegistrationStatus registrationStatus;
  final ImageCheckResult initialImageResult;
  final Future<ImageCheckResult>? imageResultFuture;
  final String? confirmedRegNumber;
  final bool isImageTrainedProduct;

  const ScanResultScreen({
    super.key,
    required this.productInfo,
    required this.status,
    required this.registrationStatus,
    required this.initialImageResult,
    this.imageResultFuture,
    this.confirmedRegNumber,
    this.isImageTrainedProduct = false,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  late ImageCheckResult _imageResult;
  bool _alertShown = false;

  @override
  void initState() {
    super.initState();
    _imageResult = widget.initialImageResult;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowSuspiciousAlert());
    widget.imageResultFuture?.then((result) {
      if (!mounted || result == _imageResult) return;
      setState(() => _imageResult = result);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowSuspiciousAlert());
    });
  }

  Map<String, double> _imageConfidenceBreakdown() {
    if (!widget.isImageTrainedProduct) return const {};
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
    double suspicious = parseScore('suspiciousScore');
    if (authentic <= 0 && suspicious <= 0) return const {};
    final total = (authentic + suspicious);
    if (total > 0) {
      authentic /= total;
      suspicious /= total;
    }
    double clamp(double v) => v.clamp(0.0, 1.0).toDouble();
    return {
      'authentic': clamp(authentic),
      'suspicious': clamp(suspicious),
    };
  }

  void _maybeShowSuspiciousAlert() {
    if (!mounted ||
        _alertShown ||
        !widget.isImageTrainedProduct ||
        _imageResult.info == null) {
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 28),
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
              const Divider(height: 24, thickness: 1, indent: 20, endIndent: 20),
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
    String titleCase(String? s) {
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

    String upperOrNA(String? s) =>
        (s == null || s.isEmpty) ? 'N/A' : s.toUpperCase();

    String niceDate(String? s) => titleCase(s);

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
    final status = widget.status;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final imageInfo = _imageResult.info;
    final imageVerdict = imageInfo?['verdict'] ?? '';
    final regNo = upperOrNA(productInfo['reg_no']);
    final sColor = statusColor(status, theme);
    final registrationColor =
        widget.registrationStatus == RegistrationStatus.registered
            ? Colors.green.shade600
            : theme.colorScheme.error;
    final imageChipValue =
        imageVerdict == 'suspicious' ? 'Suspicious' : _imageResult.status.label;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Result')),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            // Header card
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
                              titleCase(productInfo['brand_name']),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Registration No.: $regNo',
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
                    ],
                  ),
                ],
              ),
            ),

            ...() {
              final breakdown = _imageConfidenceBreakdown();
              Widget? section;
              if (widget.isImageTrainedProduct) {
                if (breakdown.isNotEmpty) {
                  section = _ImageConfidenceCard(
                    authenticScore: breakdown['authentic'] ?? 0,
                    suspiciousScore: breakdown['suspicious'] ?? 0,
                    productName: titleCase(productInfo['brand_name']),
                  );
                } else if (_imageResult.status == ImageCheckStatus.pending) {
                  section = const _InfoBanner(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Packaging check in progress',
                    message:
                        'We are comparing your photo to our reference images. Results will appear shortly.',
                  );
                } else if (_imageResult.status == ImageCheckStatus.skipped ||
                    _imageResult.status == ImageCheckStatus.failed) {
                  section = const _InfoBanner(
                    icon: Icons.image_not_supported_rounded,
                    title: 'Packaging check unavailable',
                    message:
                        'This scan did not include a usable packaging photo. Verification relies on the registration number.',
                  );
                }
              } else {
                section = const _InfoBanner(
                  icon: Icons.inventory_2_outlined,
                  title: 'Packaging reference not available',
                  message:
                      'We matched the registration record, but this SKU is not yet part of our packaging training set.',
                );
              }
              if (section == null) return <Widget>[];
              return [
                const SizedBox(height: 12),
                section,
              ];
            }(),

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
                        color: theme.colorScheme.error,
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

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: regNo));

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Registration number copied'),
                          ),
                        );
                      }
                    },

                    icon: const Icon(Icons.copy_rounded, size: 18),

                    label: const Text('Copy Reg No'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share coming soon')),
                      );
                    },

                    icon: const Icon(Icons.share_rounded, size: 18),

                    label: const Text('Share'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

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
                      icon: Icons.science_rounded,

                      label: 'Generic Name',

                      value: titleCase(productInfo['generic_name']),
                    ),

                    _DetailRow(
                      icon: Icons.category_rounded,

                      label: 'Category',

                      value: titleCase(productInfo['category']),
                    ),

                    _DetailRow(
                      icon: Icons.speed_rounded,

                      label: 'Dosage Strength',

                      value: productInfo['dosage_strength'] ?? 'N/A',
                    ),

                    _DetailRow(
                      icon: Icons.medication_rounded,

                      label: 'Dosage Form',

                      value: titleCase(productInfo['dosage_form']),
                    ),

                    _DetailRow(
                      icon: Icons.factory_rounded,

                      label: 'Manufacturer',

                      value: titleCase(productInfo['manufacturer']),
                    ),

                    _DetailRow(
                      icon: Icons.public_rounded,

                      label: 'Country',

                      value: titleCase(productInfo['country']),
                    ),

                    _DetailRow(
                      icon: Icons.local_shipping_rounded,

                      label: 'Distributor',

                      value: titleCase(productInfo['distributor']),

                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (imageProduct.isNotEmpty ||
                imageCategory.isNotEmpty ||
                imageConfidence.isNotEmpty ||
                imageSource.isNotEmpty) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.image_search_rounded),
                  title: Text(
                    imageProduct.isNotEmpty ? imageProduct : 'Image model preview',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageVerdict.isNotEmpty)
                        Text('Verdict: ${titleCase(imageVerdict)}'),
                      if (imageCategory.isNotEmpty)
                        Text('Category: ${titleCase(imageCategory)}'),
                      if (imageConfidence.isNotEmpty)
                        Text('Confidence: $imageConfidence'),
                      if (imageSource.isNotEmpty)
                        Text('Source: $imageSource'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Why it matched (if available)
            if ((productInfo['match_reason'] ?? '').isNotEmpty) ...[
              Card(
                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Icon(
                        Icons.info_outline_rounded,

                        color: theme.colorScheme.primary,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              'Why this matched',

                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Text(productInfo['match_reason'] ?? ''),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],

            // Why this status (e.g., EXPIRED or UNRECOGNIZED)
            if ((productInfo['verification_reasons'] ?? '').isNotEmpty) ...[
              Card(
                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Padding(
                  padding: const EdgeInsets.all(12),

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Icon(Icons.warning_amber_rounded, color: sColor),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              'Why this status',

                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Text(productInfo['verification_reasons'] ?? ''),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],

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

            // Report button
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

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ImageConfidenceCard extends StatelessWidget {
  final double authenticScore;
  final double suspiciousScore;
  final String productName;

  const _ImageConfidenceCard({
    required this.authenticScore,
    required this.suspiciousScore,
    required this.productName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$productName packaging confidence',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ConfidenceBar(
              label: 'Authentic cues',
              value: authenticScore,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _ConfidenceBar(
              label: 'Suspicious cues',
              value: suspiciousScore,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'These percentages come from the packaging helper model. Combine them with the registration result before making a decision.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _ConfidenceBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    final percent = (clampedValue * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: clampedValue,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
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
      color:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
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

                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final imageSummary = widget.imageInfo?['product'] ??
                          widget.imageInfo?['verdict'] ??
                          widget.imageStatus.label;
                      final summary = StringBuffer()
                        ..writeln('Suspicious Product Report')
                        ..writeln('')
                        ..writeln('Category: $_category')
                        ..writeln('Description: ${_descCtrl.text.trim()}')
                        ..writeln('Contact: ${_contactCtrl.text.trim()}')
                        ..writeln('')
                        ..writeln(
                          'Brand: ${widget.productInfo['brand_name'] ?? ''}',
                        )
                        ..writeln(
                          'Generic: ${widget.productInfo['generic_name'] ?? ''}',
                        )
                        ..writeln(
                          'Confirmed Reg No: ${widget.confirmedRegNumber ?? widget.productInfo['reg_no'] ?? ''}',
                        )
                        ..writeln(
                          'Registration Status: ${widget.registrationStatus.label}',
                        )
                        ..writeln(
                          'Image Check: $imageSummary',
                        )
                        ..writeln(
                          'Dosage: ${widget.productInfo['dosage_form'] ?? ''} ${widget.productInfo['dosage_strength'] ?? ''}',
                        )
                        ..writeln(
                          'Manufacturer: ${widget.productInfo['manufacturer'] ?? ''}',
                        )
                        ..writeln(
                          'Distributor: ${widget.productInfo['distributor'] ?? ''}',
                        )
                        ..writeln(
                          'Country: ${widget.productInfo['country'] ?? ''}',
                        );
                      final conf = widget.imageInfo?['confidence'];
                      if (conf != null && conf.isNotEmpty) {
                        summary.writeln('Image Confidence: $conf');
                      }

                      await Share.share(
                        summary.toString(),

                        subject: 'Suspicious Product Report',
                      );
                    },

                    icon: const Icon(Icons.share_rounded),

                    label: const Text('Share report via...'),
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
