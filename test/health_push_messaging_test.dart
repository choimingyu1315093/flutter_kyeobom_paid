import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/health_push_messaging.dart';

void main() {
  test('only battery <=20 and the two heat levels are allowed', () {
    expect(HealthPushAlert.fromData({
      'kind': 'health_alert', 'type': 'battery_low', 'uid': 'u1',
    })?.type, 'battery_low');
    expect(HealthPushAlert.fromData({
      'kind': 'health_alert', 'type': 'thermal_serious', 'uid': 'u1',
    })?.type, 'thermal_serious');
    expect(HealthPushAlert.fromData({
      'kind': 'health_alert', 'type': 'thermal_critical', 'uid': 'u1',
    })?.critical, isTrue);
    expect(HealthPushAlert.fromData({
      'kind': 'health_alert', 'type': 'battery_critical', 'uid': 'u1',
    }), isNull);
    expect(HealthPushAlert.fromData({
      'kind': 'health_alert', 'type': 'network_offline', 'uid': 'u1',
    }), isNull);
    expect(HealthPushAlert.fromData({
      'kind': 'untrusted', 'type': 'battery_low', 'uid': 'u1',
    }), isNull);
  });

  testWidgets('real foreground alert overlays video route without touching it',
      (tester) async {
    final notifier = HealthPushMessaging.instance.foregroundAlert;
    addTearDown(() => notifier.value = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Center(child: Text('LIVE VIDEO')),
            Positioned(top: 0, left: 0, right: 0,
                child: HealthPushForegroundBanner()),
          ]),
        ),
      ),
    );

    expect(find.text('LIVE VIDEO'), findsOneWidget);
    notifier.value = const HealthPushAlert('thermal_critical', 'user');
    await tester.pump();

    expect(find.text('거치폰 과열 위험'), findsOneWidget);
    expect(find.text('LIVE VIDEO'), findsOneWidget);

    await tester.tap(find.byTooltip('알림 닫기'));
    await tester.pump();
    expect(find.text('거치폰 과열 위험'), findsNothing);
    expect(find.text('LIVE VIDEO'), findsOneWidget);
  });
}
