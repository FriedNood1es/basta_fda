import 'package:flutter/material.dart';
import 'package:basta_fda/services/history_service.dart';
import 'package:basta_fda/screens/scan_result_screen.dart';
import 'package:basta_fda/screens/not_found_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    HistoryService.instance.load().then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final items = HistoryService.instance.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_rounded),
            tooltip: 'Export JSON',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final path = await HistoryService.instance.export();
                    if (!context.mounted) return;
                    if (path != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exported to: $path')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Export failed')),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear History',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Clear history?'),
                        content: const Text('This will remove all saved scans.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await HistoryService.instance.clear();
                      if (mounted) setState(() {});
                    }
                  },
          )
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('No scans yet'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final brand = e.productInfo?['brand_name'];
                final title = brand != null && brand.isNotEmpty ? brand : e.scannedText;
                String two(int n) => n.toString().padLeft(2, '0');
                final t = e.timestamp.toLocal();
                final ts = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
                return ListTile(
                  title: Text(title),
                  subtitle: Text('${e.status} • $ts'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    if (e.productInfo != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScanResultScreen(productInfo: e.productInfo!, status: e.status),
                        ),
                      );
                    } else {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => NotFoundScreen(scannedText: e.scannedText)));
                    }
                  },
                );
              },
            ),
    );
  }
}
