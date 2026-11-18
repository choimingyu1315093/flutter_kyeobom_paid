import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('event recording defaults off and requires station opt-in',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var optedIn = false;
    await tester.pumpWidget(MaterialApp(
      home: KyeobomStationView(
        status: '연결 대기 중',
        streaming: false,
        microphoneOn: false,
        microphoneBusy: false,
        leaving: false,
        onLeave: () {},
        onToggleMicrophone: () {},
        onEventRecordingChanged: (value) => optedIn = value,
        onViewEventClips: () {},
      ),
    ));
    expect(find.text('이벤트 자동 녹화'), findsOneWidget);
    expect(find.text('저장된 이벤트 영상 보기'), findsOneWidget);
    expect(find.textContaining('카메라 OFF · 마이크 OFF · 녹화 OFF'),
        findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile)).toList();
    expect(switches.last.value, isFalse);
    switches.last.onChanged?.call(true);
    expect(optedIn, isTrue);
  });
}
