import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_health_policy.dart';
import 'remote_control.dart';

/// Station-only OS telemetry. Never activates the camera or microphone.
/// One refresh on entry, then a low-rate heartbeat to minimize Firestore cost.
class DeviceHealthPublisher {
  DeviceHealthPublisher({this.onSample, this.onSyncError});

  final void Function(DeviceHealthSnapshot)? onSample;
  /// null clears a previous error, otherwise only a non-sensitive error code.
  final void Function(String?)? onSyncError;

  static const channel = MethodChannel('home_camera/screen');
  static const heartbeatPeriod = Duration(minutes: 2);

  Timer? _timer;
  bool _busy = false;
  bool _closed = true;

  void start() {
    if (!_closed) return;
    _closed = false;
    unawaited(refresh());
    _timer = Timer.periodic(heartbeatPeriod, (_) => unawaited(refresh()));
  }

  Future<void> refresh() async {
    if (_closed || _busy) return;
    _busy = true;
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>(
        'getDeviceHealth',
      );
      if (_closed) return;
      if (raw == null) {
        onSyncError?.call('health-unavailable');
        return;
      }
      final snapshot = DeviceHealthSnapshot.fromNative(raw, DateTime.now());
      // Safety actions use LOCAL readings even when Firebase is unavailable.
      onSample?.call(snapshot);

      if (_closed) return;
      await RemoteControl.instance.station
          .collection('telemetry').doc('health').set({
        ...snapshot.toFirestore(),
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      if (!_closed) onSyncError?.call(null);
    } catch (error) {
      // A missing internet connection or permission must never take down video.
      if (!_closed) {
        final code = error is FirebaseException
            ? error.code
            : error is PlatformException
                ? error.code
                : error is TimeoutException
                    ? 'network-timeout'
                    : 'unexpected-error';
        onSyncError?.call(code);
      }
    } finally {
      _busy = false;
    }
  }

  /// Never block screen departure on an offline Firestore write.
  /// Marking offline is best effort; the viewer also checks heartbeat age.
  void stop() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_markOffline());
  }

  Future<void> _markOffline() async {
    try {
      await RemoteControl.instance.station
          .collection('telemetry').doc('health').set({
        'active': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
    } catch (_) {
      // A stale heartbeat will independently mark the station disconnected.
    }
  }
}

/// Always compact on the home screen; tap to expand diagnostic details.
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
        _telemetry = RemoteControl.instance.station
            .collection('telemetry').doc('health').snapshots();
        // The server sends no event when the station goes silent.
        _staleCheck = Timer.periodic(const Duration(seconds: 15), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {
      // Isolated Flutter layout tests do not initialize Firebase.
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
    final stream = _telemetry;
    if (stream == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.sensors_off_outlined),
          title: Text('홈캠 상태'),
          subtitle: Text('연결 정보 없음'),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          final denied = error is FirebaseException &&
              error.code == 'permission-denied';
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.deepOrange),
              title: const Text('홈캠 상태 확인 실패'),
              subtitle: Text(denied
                  ? 'Firestore 규칙에서 상태 정보 접근이 거부됐어요.'
                  : '기기 상태를 수신하지 못했어요. 인터넷 연결을 확인해 주세요.'),
            ),
          );
        }

        final data = snapshot.data?.data();
        final seen = (data?['lastSeen'] as Timestamp?)?.toDate();
        final collected = (data?['collectedAt'] as Timestamp?)?.toDate();
        final now = DateTime.now();
        // Reject queued offline writes synchronized much later.
        final freshServer = seen != null &&
            now.difference(seen).inSeconds >= -30 &&
            now.difference(seen) < const Duration(minutes: 5);
        final freshSample = collected != null &&
            now.difference(collected).inSeconds >= -60 &&
            now.difference(collected) < const Duration(minutes: 5);
        final online = data?['active'] == true &&
            freshServer && (collected == null || freshSample);
        final current = data == null
            ? null
            : DeviceHealthSnapshot.fromNative(data, collected ?? now);
        final risk = online
            ? current?.level ?? HealthLevel.normal
            : HealthLevel.warning;
        final warning = online ? current?.warning ?? '' :
            '거치폰 앱과 네트워크 연결을 확인해 주세요.';

        final color = risk == HealthLevel.critical
            ? Colors.red.shade700
            : risk == HealthLevel.normal
                ? Colors.green.shade700
                : Colors.deepOrange.shade700;
        final status = online
            ? (risk == HealthLevel.normal ? '정상 작동' :
                risk == HealthLevel.critical ? '보호 중' : '주의 필요')
            : '연결 확인 필요';

        return Card(
          child: ExpansionTile(
            leading: Icon(
              online && risk == HealthLevel.normal
                  ? Icons.check_circle_outline
                  : Icons.health_and_safety_outlined,
              color: color,
            ),
            title: const Text('거치폰 상태',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '$status · ${current?.batteryLabel ?? "정보 없음"}',
              style: TextStyle(color: color, fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Divider(),
              _detail('연결', online ? '연결됨' : '연결 확인 필요'),
              _detail('배터리', current?.batteryLabel ?? '정보 없음'),
              _detail('기기 발열', current?.heatLabel ?? '정보 없음'),
              _detail('네트워크', current?.networkLabel ?? '정보 없음'),
              _detail('마지막 통신', seen == null
                  ? '없음' : '${seen.toLocal().toString().split(".").first}'),
              if (warning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(warning,
                    style: TextStyle(color: color, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('발열은 기기의 OS 위험 단계이며 실제 온도(℃)가 아닙니다.',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(children: [
      Expanded(child: Text(label,
        style: const TextStyle(color: Colors.grey, fontSize: 12))),
      Flexible(child: Text(value, textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]),
  );
}
