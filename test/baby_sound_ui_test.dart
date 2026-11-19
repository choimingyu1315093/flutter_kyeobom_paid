import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('baby sound is opt-in and controls remain reachable on small phone',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? toggled;
    await tester.pumpWidget(MaterialApp(home: KyeobomStationView(
      status: '연결 대기 중',
      streaming: false,
      microphoneOn: false,
      microphoneBusy: false,
      leaving: false,
      onLeave: () {},
      onToggleMicrophone: () {},
      onBabyChanged: (value) => toggled = value,
      onManagePairing: () {},
      babyStatus: '베이비 모드 꺼짐',
      eventRecordingEnabled: false,
      onEventRecordingChanged: (_) {},
      onViewEventClips: () {},
    )));
    await tester.ensureVisible(find.text('베이비 모드 · 아기 울음 감지'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('카메라 OFF · 마이크 OFF'), findsOneWidget);
    final babySwitch = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile)).last;
    expect(babySwitch.value, false);
    babySwitch.onChanged?.call(true);
    expect(toggled, true);
  });

  testWidgets('sound monitoring can always be disabled while live',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? revokedConsent;
    await tester.pumpWidget(MaterialApp(home: KyeobomStationView(
      status: '연결 대기 중',
      streaming: true,
      microphoneOn: false,
      microphoneBusy: false,
      leaving: false,
      onLeave: () {},
      onToggleMicrophone: () {},
      babyEnabled: true,
      babyRunning: false,
      onBabyChanged: (enabled) => revokedConsent = enabled,
    )));
    final babySwitch = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile)).last;
    expect(babySwitch.onChanged, isNotNull);
    babySwitch.onChanged?.call(false);
    expect(revokedConsent, false);
    expect(find.textContaining('소리 변화 감지 2회'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
