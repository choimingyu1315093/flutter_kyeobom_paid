import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/baby_sound_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_camera/screen');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('disabled by default and never opens microphone', (tester) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'readBabySoundLevel' ? -70.0 : null;
    });
    final monitor = BabySoundMonitor(
      onStatus: (_) {},
      onDetection: (_) {},
    );
    await monitor.start();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, isEmpty);
    expect(monitor.running, false);
    await monitor.stop();
  });

  testWidgets('explicit opt-in, sustained sound, then stop releases mic',
      (tester) async {
    var db = -68.0;
    var starts = 0;
    var stops = 0;
    final events = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'startBabySoundMonitoring':
          starts++;
          return null;
        case 'stopBabySoundMonitoring':
          stops++;
          return null;
        case 'readBabySoundLevel':
          return db;
      }
      throw PlatformException(code: 'unknown_method');
    });
    final monitor = BabySoundMonitor(
      onStatus: (_) {},
      onDetection: events.add,
    );
    monitor.setEnabled(true);
    await monitor.start();
    expect(starts, 1);
    expect(monitor.running, true);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(events, isEmpty);
    db = -30.0;
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(events, [1]);
    await monitor.stop();
    expect(stops, 1);
    expect(monitor.running, false);
    await tester.pump(const Duration(seconds: 2));
    expect(events, [1]);
  });

  testWidgets('handoff uses existing RTC track instead of opening a second mic', (tester) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'startBabyRtcMonitoring') {
        expect(call.arguments, {'trackId': 'station-audio'});
      }
      return call.method == 'readBabySoundLevel' ? -70.0 : null;
    });
    final monitor = BabySoundMonitor(onStatus: (_) {}, onDetection: (_) {});
    monitor.setEnabled(true);
    await monitor.start();
    await monitor.stop();
    await monitor.start(webRtcTrackId: 'station-audio');
    expect(monitor.usingRtcAudio, true);
    await monitor.start(); // Peer closes outside the manual toggle.
    expect(monitor.usingRtcAudio, false);
    await monitor.stop();
    expect(calls, ['startBabySoundMonitoring', 'stopBabySoundMonitoring',
      'startBabyRtcMonitoring', 'stopBabySoundMonitoring',
      'startBabySoundMonitoring', 'stopBabySoundMonitoring']);
    expect(monitor.running, false);
  });

}
