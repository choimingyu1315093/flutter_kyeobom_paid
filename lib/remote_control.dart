import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

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
        'commandId': 'stop-' + DateTime.now().microsecondsSinceEpoch.toString(),
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit(bool register) async {
    setState(() { busy = true; error = null; });
    try {
      await RemoteControl.instance.signIn(email.text, password.text, register: register);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/roles');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('HomeCamera 테스트 계정')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('두 기기에서 같은 테스트 계정으로 로그인하세요.'),
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '이메일')),
        TextField(controller: password, obscureText: true,
          decoration: const InputDecoration(labelText: '비밀번호')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        FilledButton(onPressed: busy ? null : () => submit(false), child: const Text('로그인')),
        TextButton(onPressed: busy ? null : () => submit(true), child: const Text('테스트 계정 만들기')),
      ]),
    ),
  );
}
