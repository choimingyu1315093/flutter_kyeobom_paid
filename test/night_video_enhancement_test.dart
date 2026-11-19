import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/night_video_enhancement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_camera/night_test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'attachNightVideo' ? true : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('A/B disabled never changes native video', () async {
    final n = NightVideoEnhancement(channel: channel, enabled: false);
    expect(await n.attach('video'), false);
    await n.detach();
    expect(calls, isEmpty);
  });
  test('same track attaches once; detach and new track are scoped', () async {
    final n = NightVideoEnhancement(channel: channel, enabled: true);
    expect(await n.attach('a'), true);
    expect(await n.attach('a'), true);
    expect(await n.attach('b'), true);
    await n.detach();
    await n.detach();
    expect(calls.map((c) => c.method), ['attachNightVideo', 'detachNightVideo',
      'attachNightVideo', 'detachNightVideo']);
    expect(calls.map((c) => c.arguments['trackId']), ['a','a','b','b']);
  });
  test('unsupported native processor never interrupts raw video', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    final n = NightVideoEnhancement(channel: channel, enabled: true);
    expect(await n.attach('a'), false);
    await n.detach();
  });
  test('platform error falls back to original video', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'not-supported');
    });
    final n = NightVideoEnhancement(channel: channel, enabled: true);
    expect(await n.attach('a'), false);
  });
}
