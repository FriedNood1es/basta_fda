import 'package:flutter/material.dart';
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
      if (mounted) setState(() { _initTried = true; _authorized = true; });
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final status = (d['status'] ?? '').toString();
              final brand = (d['brand_name'] ?? '').toString();
              final reg = (d['reg_no'] ?? '').toString();
              final reason = (d['reason'] ?? '').toString();
              final created = d['createdAt'] is Timestamp
                  ? (d['createdAt'] as Timestamp).toDate().toLocal().toString()
                  : '';
              return ListTile(
                leading: const Icon(Icons.report_gmailerrorred_rounded),
                title: Text(brand.isNotEmpty ? brand : reg),
                subtitle: Text('${status.isNotEmpty ? status : 'REPORTED'} • $created\n$reason'),
                isThreeLine: reason.isNotEmpty,
              );
            },
          );
        },
      ),
    );
  }
}
