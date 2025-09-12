import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:basta_fda/services/auth_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _initTried = false;
  String? _error;
  bool _authorized = false;
  String _search = '';
  String _resolvedFilter = 'All'; // All | Resolved | Unresolved
  String _categoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    _ensureFirebase();
  }

  Future<void> _ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      // Require sign-in
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _initTried = true;
            _error = 'Sign in required to view reports.';
          });
        }
        return;
      }
      final admin = await AuthService.instance.isAdmin();
      if (!admin) {
        if (mounted) {
          setState(() {
            _initTried = true;
            _error = 'You are not authorized to view reports.';
          });
        }
        return;
      }
      if (mounted) setState(() {
        _initTried = true;
        _authorized = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initTried = true;
          _error = 'Firebase not configured. Please run flutterfire configure.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initTried) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: Center(child: Text(_error!)),
      );
    }
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const Center(child: Text('Not authorized')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by brand or reg no',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _resolvedFilter == 'All',
                  onSelected: (_) => setState(() => _resolvedFilter = 'All'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Unresolved'),
                  selected: _resolvedFilter == 'Unresolved',
                  onSelected: (_) => setState(() => _resolvedFilter = 'Unresolved'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Resolved'),
                  selected: _resolvedFilter == 'Resolved',
                  onSelected: (_) => setState(() => _resolvedFilter = 'Resolved'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No reports yet'));
                }

                // Build category options from data
                final categories = <String>{};
                for (final doc in docs) {
                  final c = (doc.data()['category'] ?? '').toString().trim();
                  if (c.isNotEmpty) categories.add(c);
                }

                // Filters
                bool matchesResolvedFilter(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                  final resolved = doc.data()['resolvedAt'] is Timestamp;
                  switch (_resolvedFilter) {
                    case 'Resolved':
                      return resolved;
                    case 'Unresolved':
                      return !resolved;
                    default:
                      return true;
                  }
                }

                bool matchesSearch(Map<String, dynamic> d) {
                  if (_search.isEmpty) return true;
                  final brand = (d['brand_name'] ?? '').toString().toLowerCase();
                  final reg = (d['reg_no'] ?? '').toString().toLowerCase();
                  final category = (d['category'] ?? '').toString().toLowerCase();
                  final desc = (d['description'] ?? d['reason'] ?? '').toString().toLowerCase();
                  return brand.contains(_search) || reg.contains(_search) || category.contains(_search) || desc.contains(_search);
                }

                bool matchesCategory(Map<String, dynamic> d) {
                  if (_categoryFilter == 'All') return true;
                  return (d['category'] ?? '').toString() == _categoryFilter;
                }

                String fmtTs(Timestamp? ts) {
                  if (ts == null) return '';
                  final dt = ts.toDate().toLocal();
                  String two(int n) => n.toString().padLeft(2, '0');
                  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
                }

                final filtered = docs.where((doc) {
                  final d = doc.data();
                  return matchesResolvedFilter(doc) && matchesCategory(d) && matchesSearch(d);
                }).toList();

                return Column(
                  children: [
                    if (categories.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('All categories'),
                                selected: _categoryFilter == 'All',
                                onSelected: (_) => setState(() => _categoryFilter = 'All'),
                              ),
                              const SizedBox(width: 8),
                              ...categories.map((c) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(c),
                                      selected: _categoryFilter == c,
                                      onSelected: (_) => setState(() => _categoryFilter = c),
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, _) => const Divider(height: 0),
                        itemBuilder: (context, i) {
                          final doc = filtered[i];
                          final d = doc.data();
                          final status = (d['status'] ?? '').toString();
                          final brand = (d['brand_name'] ?? '').toString();
                          final reg = (d['reg_no'] ?? '').toString();
                          final reason = (d['description'] ?? d['reason'] ?? '').toString();
                          final created = d['createdAt'] is Timestamp ? fmtTs(d['createdAt'] as Timestamp) : '';
                          final resolved = d['resolvedAt'] is Timestamp;
                          final titleText = (brand.isNotEmpty ? brand : reg).trim();
                          return ListTile(
                            leading: Icon(
                              resolved ? Icons.verified_rounded : Icons.report_gmailerrorred_rounded,
                              color: resolved ? Colors.green : null,
                            ),
                            title: Text(titleText),
                            subtitle: Text('${status.isNotEmpty ? status : 'REPORTED'}  •  $created\n$reason'),
                            isThreeLine: reason.isNotEmpty,
                            trailing: resolved
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                    ),
                                    child: const Text('RESOLVED', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                                  )
                                : null,
                            onTap: () async {
                              await showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                builder: (ctx) => _ReportDetailSheet(doc: doc),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportDetailSheet extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _ReportDetailSheet({required this.doc});

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  bool _updating = false;

  Future<void> _toggleResolve() async {
    setState(() => _updating = true);
    try {
      final data = widget.doc.data();
      final resolved = data['resolvedAt'] is Timestamp;
      if (resolved) {
        await widget.doc.reference.update({
          'resolvedAt': FieldValue.delete(),
          'resolvedByUid': FieldValue.delete(),
        });
      } else {
        final user = FirebaseAuth.instance.currentUser;
        await widget.doc.reference.update({
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedByUid': user?.uid ?? 'admin',
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update report')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final resolved = d['resolvedAt'] is Timestamp;
    final created = d['createdAt'] is Timestamp
        ? (d['createdAt'] as Timestamp).toDate().toLocal().toString()
        : '';
    final resolvedAt = d['resolvedAt'] is Timestamp
        ? (d['resolvedAt'] as Timestamp).toDate().toLocal().toString()
        : '';

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.black54))),
              const SizedBox(width: 8),
              Expanded(child: Text(value.isEmpty ? '—' : value)),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    resolved ? Icons.verified_rounded : Icons.report_gmailerrorred_rounded,
                    color: resolved ? Colors.green : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (d['brand_name'] ?? d['reg_no'] ?? '').toString(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final summary = StringBuffer()
                        ..writeln('Report: ${(d['brand_name'] ?? d['reg_no'] ?? '').toString()}')
                        ..writeln('Status: ${(d['status'] ?? 'REPORTED').toString()}')
                        ..writeln('Category: ${(d['category'] ?? '').toString()}')
                        ..writeln('Description: ${(d['description'] ?? d['reason'] ?? '').toString()}')
                        ..writeln('Reg No: ${(d['reg_no'] ?? '').toString()}')
                        ..writeln('Created: $created')
                        ..writeln(resolved ? 'Resolved: $resolvedAt' : '');
                      await Clipboard.setData(ClipboardData(text: summary.toString()));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report summary copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy summary'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              row('Status', (d['status'] ?? 'REPORTED').toString()),
              row('Category', (d['category'] ?? '').toString()),
              row('Description', (d['description'] ?? d['reason'] ?? '').toString()),
              const Divider(height: 24),
              row('Registration No.', (d['reg_no'] ?? '').toString()),
              row('Brand Name', (d['brand_name'] ?? '').toString()),
              row('Generic Name', (d['generic_name'] ?? '').toString()),
              row('Dosage Form', (d['dosage_form'] ?? '').toString()),
              row('Dosage Strength', (d['dosage_strength'] ?? '').toString()),
              row('Manufacturer', (d['manufacturer'] ?? '').toString()),
              row('Distributor', (d['distributor'] ?? '').toString()),
              const Divider(height: 24),
              row('Contact', (d['contact'] ?? '').toString()),
              row('Reporter UID', (d['createdByUid'] ?? '').toString()),
              row('Reporter Email', (d['createdByEmail'] ?? '').toString()),
              row('Created At', created),
              if (resolved) row('Resolved At', resolvedAt),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _updating ? null : _toggleResolve,
                  icon: _updating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(resolved ? Icons.undo_rounded : Icons.verified_rounded),
                  label: Text(resolved ? 'Mark as Unresolved' : 'Mark as Resolved'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
