import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Generated locally by `flutterfire configure` and excluded from Git.
// Native default init can fail in an iOS QA build even with a plist present.
import 'firebase_options.dart';

import 'homecam_emulator_qa.dart';

/// Each station signs in anonymously on its own phone. The viewer signs in
/// using an email account, then must be explicitly approved on the station.
/// The Firestore rules enforce viewerUid on *every* signaling read/write.
class RemoteControl {
  RemoteControl._();
  static final instance = RemoteControl._();

  static const _pairAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _pairLength = 10;
  static const _pairLifetime = Duration(minutes: 10);
  String? _viewerStationUid;
  String? _viewerUidCached;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  User get user => FirebaseAuth.instance.currentUser!;
  bool get isStationIdentity => user.isAnonymous;

  String get stationUid {
    if (isStationIdentity) return user.uid;
    if (_viewerUidCached != user.uid || _viewerStationUid == null) {
      throw StateError('연결된 홈캠이 없습니다. 연결 코드를 입력해 주세요.');
    }
    return _viewerStationUid!;
  }

  DocumentReference<Map<String, dynamic>> get station =>
      FirebaseFirestore.instance.collection('homecamStations').doc(stationUid);

  DocumentReference<Map<String, dynamic>> stationByUid(String uid) =>
      FirebaseFirestore.instance.collection('homecamStations').doc(uid);

  CollectionReference<Map<String, dynamic>> get invitations =>
      FirebaseFirestore.instance.collection('homecamPairings');

  // Keep emulator QA pairing cache separate from real Firebase accounts.
  String _pairKey(String uid) =>
      'kyeobom_paired_station_v2_${HomeCamEmulatorQa.enabled ? "qa_" : ""}$uid';

  Future<void> restoreViewerPairing() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.isAnonymous) {
      _viewerUidCached = null;
      _viewerStationUid = null;
      return;
    }
    _viewerUidCached = current.uid;
    _viewerStationUid = await SharedPreferencesAsync().getString(
      _pairKey(current.uid),
    );
  }

  Future<void> signIn(String email, String password,
      {required bool register}) async {
    await initialize();
    if (register) {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(), password: password,
      );
    } else {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(), password: password,
      );
    }
    await restoreViewerPairing();
  }

  Future<void> signInStationAnonymously() async {
    await initialize();
    final current = FirebaseAuth.instance.currentUser;
    if (current?.isAnonymous == true) return;
    if (current != null) await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
    _viewerUidCached = null;
    _viewerStationUid = null;
  }

  Future<void> clearViewerPairing() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await SharedPreferencesAsync().remove(_pairKey(uid));
    }
    _viewerUidCached = null;
    _viewerStationUid = null;
  }

  Future<bool> viewerHasAccess() async {
    if (FirebaseAuth.instance.currentUser?.isAnonymous != false) return false;
    await restoreViewerPairing();
    final id = _viewerStationUid;
    if (id == null || id.isEmpty) return false;
    try {
      final doc = await stationByUid(id).get();
      final allowed = doc.data()?['viewerUid'] == user.uid;
      if (!allowed) await clearViewerPairing();
      return allowed;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        await clearViewerPairing();
        return false;
      }
      rethrow;
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> createPairingInvite() async {
    if (!isStationIdentity) {
      throw StateError('거치폰 전용 인증이 필요합니다.');
    }
    final data = (await station.get()).data();
    if (data?['viewerUid'] is String &&
        (data!['viewerUid'] as String).isNotEmpty) {
      throw StateError('먼저 기존 뷰어 연결을 해제해 주세요.');
    }
    final random = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(_pairLength,
          (_) => _pairAlphabet[random.nextInt(_pairAlphabet.length)]).join();
      final ref = invitations.doc(code);
      if ((await ref.get()).exists) continue;
      try {
        await ref.set({
          'stationUid': user.uid,
          'status': 'open',
          'pendingViewerUid': '',
          'pendingViewerEmail': '',
          'expiresAt': Timestamp.fromDate(DateTime.now().add(_pairLifetime)),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return ref;
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied' &&
            error.code != 'already-exists') {
          rethrow;
        }
      }
    }
    throw StateError('연결 코드 생성에 실패했습니다. 다시 시도해 주세요.');
  }

  static String normalizedCode(String code) =>
      code.replaceAll(RegExp(r'\s|-'), '').toUpperCase();

  Future<DocumentReference<Map<String, dynamic>>> requestPairing(
      String input) async {
    if (user.isAnonymous || user.email == null) {
      throw StateError('뷰어폰은 이메일 계정으로 로그인해야 합니다.');
    }
    final code = normalizedCode(input);
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{10}$').hasMatch(code)) {
      throw FormatException('거치폰의 연결 코드 10자리를 확인해 주세요.');
    }
    final ref = invitations.doc(code);
    final data = (await ref.get()).data();
    if (data == null || data['status'] != 'open' ||
        data['stationUid'] is! String ||
        data['expiresAt'] is! Timestamp ||
        (data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
      throw StateError('연결 코드가 만료되었거나 사용할 수 없습니다.');
    }
    await ref.update({
      'pendingViewerUid': user.uid,
      'pendingViewerEmail': user.email,
      'status': 'pending',
    });
    return ref;
  }

  Future<void> cancelPairingRequest(
      DocumentReference<Map<String, dynamic>> invitation) async {
    if (user.isAnonymous) return;
    await invitation.update({
      'pendingViewerUid': '',
      'pendingViewerEmail': '',
      'status': 'open',
    });
  }

  /// Only the person holding the station may approve a pending viewer.
  Future<void> approvePairing(
      DocumentReference<Map<String, dynamic>> invitation) async {
    if (!isStationIdentity) throw StateError('거치폰에서만 승인할 수 있습니다.');
    final invite = (await invitation.get()).data();
    if (invite == null || invite['stationUid'] != user.uid ||
        invite['status'] != 'pending' ||
        invite['pendingViewerUid'] is! String ||
        (invite['pendingViewerUid'] as String).isEmpty ||
        invite['pendingViewerEmail'] is! String ||
        invite['expiresAt'] is! Timestamp ||
        (invite['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
      throw StateError('승인 가능한 연결 요청이 없습니다.');
    }
    // Atomic grant: viewer cannot see a partially authorized station.
    final batch = FirebaseFirestore.instance.batch();
    batch.update(station, {
      'viewerUid': invite['pendingViewerUid'],
      'viewerEmail': invite['pendingViewerEmail'],
      'pairedAt': FieldValue.serverTimestamp(),
    });
    batch.update(invitation, {'status': 'approved'});
    await batch.commit();
  }

  Future<void> rejectPairing(
      DocumentReference<Map<String, dynamic>> invitation) async {
    if (!isStationIdentity) throw StateError('거치폰 전용 작업입니다.');
    await invitation.update({
      'status': 'open',
      'pendingViewerUid': '',
      'pendingViewerEmail': '',
    });
  }

  Future<void> revokeViewer() async {
    if (!isStationIdentity) throw StateError('거치폰 전용 작업입니다.');
    await station.update({
      'viewerUid': '',
      'viewerEmail': '',
      'pairedAt': FieldValue.delete(),
    });
  }

  Future<void> saveApprovedViewerPairing(
      DocumentReference<Map<String, dynamic>> invitation) async {
    if (user.isAnonymous) throw StateError('뷰어 계정이 필요합니다.');
    final data = (await invitation.get()).data();
    if (data == null || data['status'] != 'approved' ||
        data['pendingViewerUid'] != user.uid ||
        data['stationUid'] is! String) {
      throw StateError('아직 거치폰 승인이 완료되지 않았습니다.');
    }
    final stationId = data['stationUid'] as String;
    final stationData = (await stationByUid(stationId).get()).data();
    if (stationData?['viewerUid'] != user.uid) {
      throw StateError('거치폰 연결 권한을 확인할 수 없습니다.');
    }
    await SharedPreferencesAsync().setString(_pairKey(user.uid), stationId);
    _viewerStationUid = stationId;
    _viewerUidCached = user.uid;
  }

  Future<void> startStation() async {
    if (!isStationIdentity) {
      throw StateError('거치폰 전용 로그인 후 다시 시도해 주세요.');
    }
    if (!(await station.get()).exists) {
      await station.set({
        'viewerUid': '',
        'viewerEmail': '',
        'command': 'idle',
        'commandId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'onlineHint': true,
        'status': 'camera_off',
      });
    } else {
      // Merge is critical: entering standby must NEVER erase viewer grants.
      await station.set({
        'command': 'idle',
        'commandId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'onlineHint': true,
        'status': 'camera_off',
      }, SetOptions(merge: true));
    }
  }

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
