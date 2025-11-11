import 'package:flutter/material.dart';
import 'package:basta_fda/models/scan_verdict.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';

class NotFoundScreen extends StatefulWidget {
  final String scannedText;
  final FDAChecker? fdaChecker;
  final Map<String, String>? imageInfo;
  final ImageCheckStatus imageStatus;

  const NotFoundScreen({
    super.key,
    required this.scannedText,
    this.fdaChecker,
    this.imageInfo,
    required this.imageStatus,
  });

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.label,
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
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
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.6,
                  color: color,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundScreenState extends State<NotFoundScreen> {
  List<Map<String, String>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    if (widget.fdaChecker != null) {
      _suggestions = widget.fdaChecker!.topMatches(
        widget.scannedText,
        limit: 5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color imageChipColor;
    switch (widget.imageStatus) {
      case ImageCheckStatus.recognized:
        imageChipColor = theme.colorScheme.primary;
        break;
      case ImageCheckStatus.unrecognized:
        imageChipColor = theme.colorScheme.tertiary;
        break;
      case ImageCheckStatus.failed:
        imageChipColor = theme.colorScheme.error;
        break;
      case ImageCheckStatus.skipped:
        imageChipColor = theme.colorScheme.outline;
        break;
      case ImageCheckStatus.pending:
        imageChipColor = theme.colorScheme.outlineVariant;
        break;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('No Match Found')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'No matching product found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'This could mean the label text did not match FDA records or the scan missed a detail. Check the packaging, then rescan or edit the text before assuming it is counterfeit.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                label: 'Registration',
                value: 'Unregistered',
                color: theme.colorScheme.error,
                icon: Icons.rule_folder_rounded,
              ),
              _StatusChip(
                label: 'Image',
                value: widget.imageStatus.label,
                color: imageChipColor,
                icon: Icons.image_search_rounded,
              ),
            ],
          ),
          if (widget.imageStatus.needsWarning) ...[
            const SizedBox(height: 8),
            _WarningBanner(
              message:
                  'Registration verification completed without image evidence. Inspect the packaging manually or capture a photo for the helper model.',
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Scanned Text',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.scannedText.isNotEmpty
                    ? widget.scannedText
                    : 'No text extracted',
              ),
            ),
          ),
          if (widget.imageInfo != null) ...[
            const SizedBox(height: 16),
            Text(
              'Image recognition (preview)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.image_search_rounded),
                title: Text(widget.imageInfo?['product'] ?? 'Unrecognized product'),
                subtitle: Builder(
                  builder: (_) {
                    final verdict = widget.imageInfo?['verdict'] ?? '';
                    final lines = <String>[];
                    if (verdict.isNotEmpty) {
                      final label = verdict[0].toUpperCase() + verdict.substring(1);
                      lines.add('Verdict: $label');
                    }
                    lines.add(
                      'Category: ${widget.imageInfo?['category'] ?? 'unknown'}',
                    );
                    lines.add(
                      'Confidence: ${(widget.imageInfo?['confidence'] ?? '--')}',
                    );
                    lines.add('Source: ${widget.imageInfo?['source'] ?? 'n/a'}');
                    return Text(lines.join('\n'));
                  },
                ),
              ),
            ),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Nearest matches',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ..._suggestions.take(5).map((p) {
              final brand = (p['brand_name'] ?? '').isEmpty
                  ? 'Unknown'
                  : p['brand_name']!;
              final strength = (p['dosage_strength'] ?? '').isEmpty
                  ? ''
                  : ' - ${p['dosage_strength']!}';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.medication_rounded),
                  title: Text(brand),
                  subtitle: Text((p['generic_name'] ?? '')),
                  trailing: strength.isNotEmpty ? Text(strength) : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanResultScreen(
                          productInfo: p,
                          status: 'RECOGNIZED',
                          registrationStatus: RegistrationStatus.registered,
                          initialImageResult: const ImageCheckResult(
                            status: ImageCheckStatus.skipped,
                          ),
                          imageResultFuture: null,
                          confirmedRegNumber: p['reg_no'],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, widget.scannedText),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit & Retry'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go Back'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
