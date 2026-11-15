import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_cost_policy.dart';

void main() {
  group('Firestore-free WebRTC liveness policy', () {
    test('heartbeat is session-scoped and rejects stale/foreign packets', () {
      final value = HomeCamCostPolicy.heartbeat('session-A');
      expect(value, 'kb-live-v1:session-A');
      expect(HomeCamCostPolicy.isHeartbeatForSession(value, 'session-A'), isTrue);
      expect(HomeCamCostPolicy.isHeartbeatForSession(value, 'session-B'), isFalse);
      expect(HomeCamCostPolicy.isHeartbeatForSession(value, ''), isFalse);
      expect(HomeCamCostPolicy.isHeartbeatForSession('hello', 'session-A'), isFalse);
      expect(
        HomeCamCostPolicy.isHeartbeatForSession(
          'kb-live-v1:session-A-suffix', 'session-A',
        ),
        isFalse,
      );
    });

    test('45-second inactivity is fail-closed with 10-second pulse interval', () {
      const pulse = HomeCamCostPolicy.heartbeatPeriod;
      const timeout = HomeCamCostPolicy.stationTimeout;
      expect(pulse, const Duration(seconds: 10));
      expect(HomeCamCostPolicy.watchdogPeriod, const Duration(seconds: 5));
      expect(timeout, const Duration(seconds: 45));

      final t0 = DateTime(2026, 11, 15);
      expect(HomeCamCostPolicy.stationTimedOut(t0,
          t0.add(const Duration(seconds: 44))), isFalse);
      expect(HomeCamCostPolicy.stationTimedOut(t0,
          t0.add(const Duration(seconds: 45))), isFalse);
      expect(HomeCamCostPolicy.stationTimedOut(t0,
          t0.add(const Duration(seconds: 46))), isTrue);
      final lastSuccessfulPing = t0.add(const Duration(seconds: 40));
      expect(HomeCamCostPolicy.stationTimedOut(
          lastSuccessfulPing, t0.add(const Duration(seconds: 60))), isFalse);
    });

    test('relay is disabled and cannot generate TURN traffic charges', () {
      final config = HomeCamCostPolicy.directIceConfig;
      final servers = config['iceServers'] as List<dynamic>;
      expect(servers, isNotEmpty);
      for (final server in servers) {
        final map = server as Map<String, dynamic>;
        final rawUrls = map['urls'];
        final urls = rawUrls is String ? [rawUrls] : (rawUrls as List).cast<String>();
        expect(urls, isNotEmpty);
        for (final url in urls) {
          expect(url.startsWith('stun:'), isTrue);
          expect(url.startsWith('turn:'), isFalse);
          expect(url.startsWith('turns:'), isFalse);
        }
      }
    });
  });
}
