import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'remote_control.dart';

/// Low-frequency telemetry only. Never starts a camera or microphone.
class DeviceHealthPublisher {
  DeviceHealthPublisher({this.onThermalWarning});
  final void Function(bool)? onThermalWarning;
  static const channel = MethodChannel('home_camera/screen');
  Timer? _timer;
  bool _busy = false;
  bool _closed = false;

  void start() {
    _closed = false;
    unawaited(_publish());
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => unawaited(_publish()));
  }

  Future<void> _publish() async {
    if (_closed || _busy) return;
    _busy = true;
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>('getDeviceHealth');
      if (_closed || raw == null) return;
      final thermal = raw['thermal'] as int? ?? -1;
      onThermalWarning?.call(thermal >= ((raw['platform'] == 'iOS' ? 2 : 3)));
      await RemoteControl.instance.station.collection('telemetry').doc('health').set({
        'battery': raw['battery'],
        'charging': raw['charging'],
        'thermal': thermal,
        'network': raw['network'],
        'platform': defaultTargetPlatform.name,
        'lastSeen': FieldValue.serverTimestamp(),
        'active': true,
      }, SetOptions(merge: true));
    } catch (_) {
      // A transient network/platform failure must not interrupt WebRTC.
    } finally {
      _busy = false;
    }
  }


  Future<void> stop() async {
    _closed = true;
    _timer?.cancel();
    try {
      await RemoteControl.instance.station.collection('telemetry').doc('health').set({
        'active': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// The status widget is also rendered by isolated layout/widget tests.
/// It must never request a Firestore instance before Firebase exists.
class DeviceHealthCard extends StatefulWidget {
  const DeviceHealthCard({super.key});

  @override
  State<DeviceHealthCard> createState() => _DeviceHealthCardState();
}

class _DeviceHealthCardState extends State<DeviceHealthCard> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _telemetry;
  Timer? _staleCheck;

  @override
  void initState() {
    super.initState();
    try {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null) {
        // Reuse the same subscription across periodic UI refreshes.
        _telemetry = RemoteControl.instance.station
            .collection('telemetry')
            .doc('health')
            .snapshots();
        // Firestore won't emit a new snapshot when a powered-off station
        // stops writing. Recalculate heartbeat freshness on a local timer.
        _staleCheck = Timer.periodic(const Duration(seconds: 15), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {
      // Standalone widget tests and signed-out views have no Firebase app.
      _telemetry = null;
    }
  }

  @override
  void dispose() {
    _staleCheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = _telemetry;
    if (telemetry == null) {
      return const _DeviceHealthUnavailable();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: telemetry,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _DeviceHealthUnavailable();
        }
        final data = snapshot.data?.data();
        final seen = (data?['lastSeen'] as Timestamp?)?.toDate();
        final fresh = seen != null &&
            DateTime.now().difference(seen).inSeconds < 110;
        final online = data?['active'] == true && fresh;
        final battery = data?['battery'] as int?;
        final charging = data?['charging'] == true;
        final thermal = data?['thermal'] as int? ?? -1;
        final ios = data?['platform'] == 'iOS';
        final heat = thermal < 0
            ? '정보 없음'
            : ios
                ? (thermal >= 2 ? '높음' : thermal == 1 ? '주의' : '정상')
                : (thermal >= 3 ? '높음' : thermal >= 1 ? '주의' : '정상');
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '거치폰 상태 · ${online ? "연결됨" : "연결 확인 필요"}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '배터리: ${battery == null || battery < 0 ? "정보 없음" : "$battery%"} ${charging ? "· 충전 중" : ""}',
                ),
                Text('발열: $heat'),
                Text('네트워크: ${data?['network'] ?? "정보 없음"}'),
                Text(
                  '마지막 통신: ${seen == null ? "없음" : seen.toLocal().toString().split(".").first}',
                ),
                if (!online)
                  const Text(
                    '거치폰 앱과 네트워크 연결을 확인하세요.',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceHealthUnavailable extends StatelessWidget {
  const _DeviceHealthUnavailable();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('거치폰 상태 · 연결 정보 없음'),
        ),
      );
}
