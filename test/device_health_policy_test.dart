import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/device_health_policy.dart';

void main() {
  final now = DateTime(2026, 11, 17, 12);

  DeviceHealthSnapshot sample({
    String platform = 'android',
    int battery = 65,
    bool charging = true,
    int thermal = 0,
    String network = 'wifi',
  }) => DeviceHealthSnapshot.fromNative({
    'platform': platform,
    'battery': battery,
    'charging': charging,
    'thermal': thermal,
    'network': network,
  }, now);

  group('device health safety policy', () {
    test('healthy device retains original video quality', () {
      final health = sample();
      expect(health.level, HealthLevel.normal);
      expect(health.canStartVideo, isTrue);
      expect(health.shouldReduceVideo, isFalse);
      expect(health.shouldStopVideo, isFalse);
      expect(health.heatLabel, '정상');
    });

    test('unplugged battery at 20 percent requests lower video quality', () {
      final health = sample(battery: 20, charging: false);
      expect(health.level, HealthLevel.reduced);
      expect(health.shouldReduceVideo, isTrue);
      expect(health.shouldStopVideo, isFalse);
      expect(health.warning, contains('20%'));
    });

    test('battery at 5 percent without charger must protect the phone', () {
      final health = sample(battery: 5, charging: false);
      expect(health.level, HealthLevel.critical);
      expect(health.shouldStopVideo, isTrue);
      expect(health.canStartVideo, isFalse);
    });

    test('charging suspends low-battery protection', () {
      final health = sample(battery: 5, charging: true);
      expect(health.shouldReduceVideo, isFalse);
      expect(health.shouldStopVideo, isFalse);
    });

    test('Android moderate heat warns, severe reduces, critical stops', () {
      expect(sample(thermal: 2).level, HealthLevel.warning);
      expect(sample(thermal: 3).level, HealthLevel.reduced);
      expect(sample(thermal: 4).shouldStopVideo, isTrue);
    });

    test('iOS fair heat warns, serious reduces, critical stops', () {
      expect(sample(platform: 'iOS', thermal: 1).level, HealthLevel.warning);
      expect(sample(platform: 'iOS', thermal: 2).shouldReduceVideo, isTrue);
      expect(sample(platform: 'iOS', thermal: 3).shouldStopVideo, isTrue);
    });

    test('offline is warning but must not permanently block a recovered stream', () {
      final health = sample(network: 'offline');
      expect(health.level, HealthLevel.warning);
      expect(health.warning, contains('인터넷'));
      expect(health.shouldStopVideo, isFalse);
    });

    test('device without battery measurement does not falsely stop video', () {
      final health = sample(battery: -1, thermal: -1);
      expect(health.battery, isNull);
      expect(health.heatLabel, '측정 불가');
      expect(health.shouldStopVideo, isFalse);
      expect(health.toFirestore()['battery'], -1);
    });

    test('timestamps represent sample time to detect delayed replay', () {
      final health = sample(network: 'cellular', charging: false);
      expect(health.toFirestore()['collectedAt'], now);
      expect(health.networkLabel, '모바일 데이터');
    });
  });
}
