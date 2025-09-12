import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:basta_fda/services/settings_service.dart';

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
                color: primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                onPressed: () async {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (ctx) => _ReportProductSheet(productInfo: productInfo, status: status),
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
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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

class _ReportProductSheet extends StatefulWidget {
  final Map<String, String> productInfo;
  final String status;
  const _ReportProductSheet({required this.productInfo, required this.status});

  @override
  State<_ReportProductSheet> createState() => _ReportProductSheetState();
}

class _ReportProductSheetState extends State<_ReportProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String _category = 'Counterfeit';
  bool _submitting = false;

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
        } else if (s == 'ALERT') {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('reports').add({
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
        'reason': widget.productInfo['verification_reasons'] ?? widget.productInfo['match_reason'] ?? '',
        'appSource': 'scan_result_screen',
      });
      // Remember last inputs
      SettingsService.instance.lastReportCategory = _category;
      SettingsService.instance.lastReportContact = _contactCtrl.text.trim();
      await SettingsService.instance.save();
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Report submitted')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not submit report. Configure Firebase.')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                    const Icon(Icons.report_gmailerrorred_rounded, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    const Text('Report Suspicious Product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _category,
                  items: const [
                    DropdownMenuItem(value: 'Counterfeit', child: Text('Counterfeit')),
                    DropdownMenuItem(value: 'Tampered', child: Text('Tampered')),
                    DropdownMenuItem(value: 'Expired in market', child: Text('Expired in market')),
                    DropdownMenuItem(value: 'Adverse effect', child: Text('Adverse effect')),
                    DropdownMenuItem(value: 'Incorrect label', child: Text('Incorrect label')),
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
                    hintText: 'What seems suspicious? Where purchased? Any details…',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please provide a short description' : null,
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
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(_submitting ? 'Submitting…' : 'Submit Report'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final summary = StringBuffer()
                        ..writeln('Suspicious Product Report')
                        ..writeln('')
                        ..writeln('Category: $_category')
                        ..writeln('Description: ${_descCtrl.text.trim()}')
                        ..writeln('Contact: ${_contactCtrl.text.trim()}')
                        ..writeln('')
                        ..writeln('Brand: ${widget.productInfo['brand_name'] ?? ''}')
                        ..writeln('Generic: ${widget.productInfo['generic_name'] ?? ''}')
                        ..writeln('Reg No: ${widget.productInfo['reg_no'] ?? ''}')
                        ..writeln('Status: ${widget.status}')
                        ..writeln('Dosage: ${widget.productInfo['dosage_form'] ?? ''} ${widget.productInfo['dosage_strength'] ?? ''}')
                        ..writeln('Manufacturer: ${widget.productInfo['manufacturer'] ?? ''}')
                        ..writeln('Distributor: ${widget.productInfo['distributor'] ?? ''}')
                        ..writeln('Country: ${widget.productInfo['country'] ?? ''}');
                      await Share.share(summary.toString(), subject: 'Suspicious Product Report');
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
