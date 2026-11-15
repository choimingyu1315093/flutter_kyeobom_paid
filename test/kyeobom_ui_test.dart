import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_design.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('role card keeps its action interactive', (tester) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: KyeobomTheme.light,
        home: Scaffold(
          body: Center(
            child: KyeobomRoleCard(
              icon: Icons.videocam_outlined,
              title: '홈캠으로 사용',
              subtitle: '집에 두고 카메라를 대기시켜요.',
              onTap: () => selected = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('홈캠으로 사용'), findsOneWidget);
    await tester.tap(find.text('홈캠으로 사용'));
    expect(selected, isTrue);
  });

  testWidgets('station is dark and keeps microphone action', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(MaterialApp(
      theme: KyeobomTheme.light,
      home: KyeobomStationView(
        status: '연결됨',
        streaming: true,
        microphoneOn: false,
        microphoneBusy: false,
        leaving: false,
        onLeave: () {},
        onToggleMicrophone: () => toggles++,
      ),
    ));
    expect(find.text('영상 송출 중'), findsOneWidget);
    expect(find.textContaining('마이크 OFF'), findsOneWidget);
    await tester.tap(find.text('거치폰 마이크 켜기'));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('viewer starts live mode from a single primary action',
      (tester) async {
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KyeobomTheme.light,
        home: KyeobomViewerView(
          video: const ColoredBox(color: Colors.black),
          status: '실시간 보기를 누르면 원격 연결합니다',
          watching: false,
          busy: false,
          leaving: false,
          landscape: false,
          remoteAudioOn: false,
          onBack: () {},
          onStart: () => starts++,
          onStop: () {},
        ),
      ),
    );
    expect(find.text('우리 집, 궁금할 때'), findsOneWidget);
    await tester.tap(find.text('실시간 보기'));
    expect(starts, 1);
  });
}
