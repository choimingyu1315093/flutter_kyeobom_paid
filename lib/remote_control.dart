import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// P2 uses the SAME test account on both phones. Do not use in production
/// without a proper device-pairing and access revocation flow.
class RemoteControl {
  RemoteControl._();
  static final instance = RemoteControl._();

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  User get user => FirebaseAuth.instance.currentUser!;
  DocumentReference<Map<String, dynamic>> get station =>
      FirebaseFirestore.instance.collection('homecamStations').doc(user.uid);

  Future<void> signIn(String email, String password, {required bool register}) async {
    await initialize();
    if (register) {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    } else {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    }
  }

  Future<void> startStation() => station.set({
        'command': 'idle',
        'commandId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'onlineHint': true,
        'status': 'camera_off',
      });

  DocumentReference<Map<String, dynamic>> session(String id) =>
      station.collection('sessions').doc(id);

  Future<void> requestStart(String id) => station.set({
        'command': 'start',
        'sessionId': id,
        'commandId': id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> requestStop(String id) => station.set({
        'command': 'stop',
        'sessionId': id,
        'commandId': 'stop-${DateTime.now().microsecondsSinceEpoch}',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch() => station.snapshots();

  Future<void> acknowledge(String id, String status) => station.set({
        'ackId': id,
        'status': status,
        'ackAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> stopStation() => station.set({
        'onlineHint': false,
        'command': 'idle',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

