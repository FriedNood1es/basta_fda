import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class ScanResultScreen extends StatelessWidget {
  final Map<String, String> productInfo;
  final String status;

  const ScanResultScreen({
    super.key,
    required this.productInfo,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    String titleCase(String? s) {
      if (s == null || s.isEmpty) return 'N/A';
      return s
          .split(' ')
          .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')))
          .join(' ');
    }

    String upperOrNA(String? s) => (s == null || s.isEmpty) ? 'N/A' : s.toUpperCase();
    String niceDate(String? s) => titleCase(s);

  Color statusColor(String status, ThemeData theme) {
    switch (status.toUpperCase()) {
      case 'VERIFIED':
        return Colors.green.shade600;
      case 'EXPIRED':
        return Colors.orange.shade700;
      case 'ALERT':
        return theme.colorScheme.error;
      case 'NOT FOUND':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.primary;
    }
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final regNo = upperOrNA(productInfo['reg_no']);
    final sColor = statusColor(status, theme);

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
                color: primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: primary.withOpacity(0.1),
                    child: Image.asset('assets/logo.png', height: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleCase(productInfo['brand_name']),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Registration No.: $regNo',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Last Updated: ${niceDate(productInfo['issuance_date'])}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(label: status, color: sColor),
                ],
              ),
            ),

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
                          const SnackBar(content: Text('Registration number copied')),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

            // Why it matched (if available)
            if ((productInfo['match_reason'] ?? '').isNotEmpty) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Why this matched', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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

            // Why this status (e.g., EXPIRED or ALERT)
            if ((productInfo['verification_reasons'] ?? '').isNotEmpty) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            Text('Why this status', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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

            // Report button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report submitted')),
                  );
                },
                icon: const Icon(Icons.report_gmailerrorred_rounded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                label: const Text('Report Suspicious Product'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
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
          title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          subtitle: Text(value, style: theme.textTheme.bodyMedium),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          minLeadingWidth: 24,
        ),
        if (showDivider) const Divider(height: 0),
      ],
    );
  }
}
