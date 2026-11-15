import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'kyeobom_design.dart';

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
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 38, 28, 28),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(child: KyeobomMark(size: 98)),
                      const SizedBox(height: 26),
                      const Center(
                        child: Text(
                          '켜봄',
                          style: TextStyle(
                            color: KyeobomPalette.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          '궁금할 때, 켜봄.',
                          style: TextStyle(
                            color: KyeobomPalette.muted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 55),
                      const Text(
                        '반가워요!',
                        style: TextStyle(
                          color: KyeobomPalette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 25,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        '안 쓰는 스마트폰을 우리 집 홈캠으로.',
                        style: TextStyle(
                          color: KyeobomPalette.muted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        '이메일',
                        style: TextStyle(
                          color: KyeobomPalette.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '비밀번호',
                        style: TextStyle(
                          color: KyeobomPalette.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      TextField(
                        controller: password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!busy) submit(false);
                        },
                        decoration: const InputDecoration(
                          hintText: '비밀번호 입력',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Color(0xFFB4493F),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : () => submit(false),
                          child: Text(busy ? '로그인 중...' : '로그인'),
                        ),
                      ),
                      const SizedBox(height: 13),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: busy ? null : () => submit(true),
                          child: const Text('테스트 계정 만들기'),
                        ),
                      ),
                      const SizedBox(height: 25),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF2EF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 19,
                              color: KyeobomPalette.deepTeal,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '현재 테스트 버전입니다. 두 스마트폰에서 같은 테스트 계정으로 로그인해 주세요.',
                                style: TextStyle(
                                  color: KyeobomPalette.deepTeal,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
