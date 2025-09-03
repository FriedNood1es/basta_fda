import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'firebase_bootstrap.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Future<void> _ensure() async {
    await tryInitFirebase();
  }

  User? get currentUser => Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;

  Future<(bool ok, String? error)> signInWithEmailPassword(String email, String password) async {
    try {
      await _ensure();
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      return (true, null);
    } on FirebaseAuthException catch (e) {
      return (false, e.message);
    } catch (e) {
      return (false, 'Sign in failed');
    }
  }

  Future<(bool ok, String? error)> registerWithEmailPassword(String email, String password, {String? displayName}) async {
    try {
      await _ensure();
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      if (displayName != null && displayName.isNotEmpty) {
        await cred.user?.updateDisplayName(displayName);
      }
      return (true, null);
    } on FirebaseAuthException catch (e) {
      return (false, e.message);
    } catch (e) {
      return (false, 'Registration failed');
    }
  }

  Future<(bool ok, String? error)> signInWithGoogle() async {
    try {
      await _ensure();
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return (false, 'Sign-in aborted');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      return (true, null);
    } on FirebaseAuthException catch (e) {
      return (false, e.message);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Google sign-in failed: $e');
      }
      return (false, 'Google sign-in failed');
    }
  }

  Future<void> signOut() async {
    try {
      await _ensure();
      await FirebaseAuth.instance.signOut();
      try { await GoogleSignIn().signOut(); } catch (_) {}
    } catch (_) {}
  }

  /// Simple admin check: returns true if a document exists at `admins/{uid}`.
  Future<bool> isAdmin() async {
    try {
      await _ensure();
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return false;
      final doc = await FirebaseFirestore.instance.collection('admins').doc(u.uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}

