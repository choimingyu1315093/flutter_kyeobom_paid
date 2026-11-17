import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only the three critical station-health notifications requested by users.
/// These are FCM messages, not local simulated threshold warnings.
class HealthPushAlert {
  const HealthPushAlert(this.type, this.uid);

  final String type;
  final String uid;

  static HealthPushAlert? fromData(Map<String, dynamic> data) {
    if (data['kind'] != 'health_alert') return null;
    final type = data['type'];
    final uid = data['uid'];
    if (uid is! String || uid.isEmpty) return null;
    if (type != 'battery_low' &&
        type != 'thermal_serious' &&
        type != 'thermal_critical') return null;
    return HealthPushAlert(type as String, uid);
  }

  String get title {
    switch (type) {
      case 'battery_low':
        return '거치폰 배터리 부족';
      case 'thermal_serious':
        return '거치폰 발열 높음';
      default:
        return '거치폰 과열 위험';
    }
  }

  String get message {
    switch (type) {
      case 'battery_low':
        return '배터리가 20% 이하예요. 충전기를 연결해 주세요.';
      case 'thermal_serious':
        return '발열이 심해 영상 품질을 낮추고 있어요.';
      default:
        return '기기 보호를 위해 영상 송출이 제한됐어요.';
    }
  }

  bool get critical => type == 'thermal_critical';
}

/// One device installation has one immutable ID. A station must not receive
/// its own FCM messages even though both phones share a Firebase Auth UID.
/// Viewer role registration persists if the app goes into the background.
class HealthPushMessaging {
  HealthPushMessaging._();
  static final instance = HealthPushMessaging._();

  final ValueNotifier<HealthPushAlert?> foregroundAlert = ValueNotifier(null);
  /// Visible only when the viewer cannot register for notifications.
  final ValueNotifier<String?> setupWarning = ValueNotifier(null);
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<String>? _tokenChanges;
  Timer? _hideTimer;
  Future<String>? _installationIdFuture;
  String _role = 'none';
  int _roleRevision = 0;
  String? _lastMessageId;

  Future<String> _installationId() =>
      _installationIdFuture ??= _readInstallationId();

  Future<String> _readInstallationId() async {
    const key = 'kyeobom_health_push_installation_id_v1';
    final prefs = SharedPreferencesAsync();
    final previous = await prefs.getString(key);
    if (previous != null && previous.isNotEmpty) return previous;
    final secure = Random.secure();
    final id = List<int>.generate(16, (_) => secure.nextInt(256))
        .map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(key, id);
    return id;
  }

  DocumentReference<Map<String, dynamic>>? _deviceDoc(String uid, String id) {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseFirestore.instance.collection('homecamStations')
        .doc(uid).collection('devices').doc(id);
  }

  void _startListeners() {
    _messages ??= FirebaseMessaging.onMessage.listen((message) {
      if (_role != 'viewer') return;
      if (message.messageId != null && message.messageId == _lastMessageId) {
        return;
      }
      final alert = HealthPushAlert.fromData(message.data);
      if (alert == null) return;
      if (FirebaseAuth.instance.currentUser?.uid != alert.uid) return;
      _lastMessageId = message.messageId;
      foregroundAlert.value = alert;
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 8), dismiss);
    });
    _tokenChanges ??= FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (_role == 'viewer' && token.isNotEmpty) {
        unawaited(_registerToken(token, _roleRevision));
      }
    });
  }

  Future<void> _writeRole(String role, String? token, int revision) async {
    if (revision != _roleRevision) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final id = await _installationId();
    if (revision != _roleRevision ||
        FirebaseAuth.instance.currentUser?.uid != uid) return;
    final doc = _deviceDoc(uid, id);
    if (doc == null) return;
    await doc.set({
      'role': role,
      'fcmToken': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
  }

  Future<void> _registerToken(String token, int revision) async {
    if (revision != _roleRevision || _role != 'viewer') return;
    try {
      await _writeRole('viewer', token, revision);
      if (revision == _roleRevision) setupWarning.value = null;
    } catch (error) {
      if (revision == _roleRevision) {
        setupWarning.value = '위험 알림 기기 등록에 실패했어요. 인터넷 연결을 확인해 주세요.';
      }
      if (kDebugMode) debugPrint('[kyeobom/push] token registration unavailable: $error');
    }
  }

  Future<void> activateViewer() async {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) return;
    _role = 'viewer';
    final revision = ++_roleRevision;
    setupWarning.value = null;
    try {
      _startListeners();
      // The in-app banner handles the foreground case, including landscape
      // live video. Disable duplicated iOS foreground system banners.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false, badge: false, sound: false);
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true);
      if (revision != _roleRevision) return;
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        setupWarning.value = '위험 알림을 받으려면 기기 설정에서 알림 권한을 허용해 주세요.';
        await _writeRole('viewer', null, revision);
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // APNs is asynchronous on a newly installed signed iPhone.
        // A missing APNs token must not cause a crash or invalid FCM token.
        String? apns;
        for (var attempt = 0; attempt < 4; attempt++) {
          if (revision != _roleRevision) return;
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (apns == null || revision != _roleRevision) {
          if (revision == _roleRevision) {
            setupWarning.value = 'iPhone 푸시 등록 실패 · APNs 권한·서명을 확인해 주세요.';
          }
          await _writeRole('viewer', null, revision);
          return;
        }
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (revision != _roleRevision) return;
      if (token == null || token.isEmpty) {
        setupWarning.value = '위험 알림 토큰을 발급받지 못했어요. 다시 연결해 주세요.';
        await _writeRole('viewer', null, revision);
        return;
      }
      await _writeRole('viewer', token, revision);
      if (revision == _roleRevision) setupWarning.value = null;
    } catch (error) {
      // Missing APNs key/permission or offline Firestore must not interrupt
      // video, audio, station setup or advertising.
      if (revision == _roleRevision) {
        setupWarning.value = '위험 알림 등록 실패 · Firebase/알림 권한을 확인해 주세요.';
      }
      if (kDebugMode) debugPrint('[kyeobom/push] viewer registration failed: $error');
    }
  }

  Future<void> activateStation() async {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) return;
    _role = 'station';
    final revision = ++_roleRevision;
    setupWarning.value = null;
    dismiss();
    try {
      // Clear any previous viewer registration on this physical phone.
      await _writeRole('station', null, revision);
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/push] role update unavailable: $error');
    }
  }

  /// Called before Firebase Auth sign-out to revoke this device's subscription.
  Future<void> signOut() async {
    _role = 'none';
    ++_roleRevision;
    setupWarning.value = null;
    dismiss();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final id = await _installationId();
        await _deviceDoc(uid, id)?.delete().timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  void dismiss() {
    _hideTimer?.cancel();
    foregroundAlert.value = null;
  }
}

/// A real FCM foreground message remains visible while the viewer is in
/// full-screen landscape mode. It never pauses/stops the video connection.
class HealthPushForegroundBanner extends StatelessWidget {
  const HealthPushForegroundBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HealthPushAlert?>(
    valueListenable: HealthPushMessaging.instance.foregroundAlert,
    builder: (context, alert, _) {
      if (alert == null) return const SizedBox.shrink();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Material(
            elevation: 8,
            color: alert.critical
                ? const Color(0xFF84252A) : const Color(0xFF202A44),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber_rounded,
                color: Colors.white),
              title: Text(alert.title, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
              subtitle: Text(alert.message, style: const TextStyle(
                color: Colors.white, fontSize: 12)),
              trailing: IconButton(
                tooltip: '알림 닫기',
                onPressed: HealthPushMessaging.instance.dismiss,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    },
  );
}
