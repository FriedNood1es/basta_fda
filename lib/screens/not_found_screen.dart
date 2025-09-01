import 'package:flutter/material.dart';
import 'package:basta_fda/services/fda_checker.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';

class NotFoundScreen extends StatefulWidget {
  final String scannedText;
  final FDAChecker? fdaChecker;

  const NotFoundScreen({super.key, required this.scannedText, this.fdaChecker});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen> {
  List<Map<String, String>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    if (widget.fdaChecker != null) {
      _suggestions = widget.fdaChecker!.topMatches(widget.scannedText, limit: 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    Icon(Icons.search_off_rounded, size: 40, color: theme.colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('No matching product found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('Try scanning again with the brand and generic visible, or edit the text and retry.'),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Scanned Text', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.scannedText.isNotEmpty ? widget.scannedText : 'No text extracted'),
              ),
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Nearest matches', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._suggestions.take(5).map((p) {
                final brand = (p['brand_name'] ?? '').isEmpty ? 'Unknown' : p['brand_name']!;
                final strength = (p['dosage_strength'] ?? '').isEmpty ? '' : ' • ${p['dosage_strength']!}';
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
                          builder: (_) => ScanResultScreen(productInfo: p, status: 'VERIFIED'),
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
