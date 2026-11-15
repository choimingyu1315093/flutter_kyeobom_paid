import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';
import 'package:flutter_home_camera/kyeobom_viewer_ads.dart';

void main() {
  KyeobomViewerView createViewer({
    bool landscape = false,
    bool watching = false,
    bool busy = false,
  }) => KyeobomViewerView(
    video: const ColoredBox(color: Colors.black),
    status: '연결 대기 중',
    watching: watching,
    busy: busy,
    leaving: false,
    landscape: landscape,
    remoteAudioOn: false,
    onBack: () {},
    onStart: () {},
    onStop: () {},
  );

  testWidgets('viewer dashboard is the ONLY ad placement', (tester) async {
    await tester.pumpWidget(MaterialApp(home: createViewer()));
    expect(find.byType(KyeobomViewerHomeAd), findsOneWidget);
    expect(find.text('실시간 보기'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: createViewer(busy: true)),
    );
    expect(find.byType(KyeobomViewerHomeAd), findsNothing);
  });

  testWidgets('ads unmount before live video and remain absent in landscape',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: createViewer(landscape: true, watching: true),
    ));
    expect(find.byType(KyeobomViewerHomeAd), findsNothing);
    expect(find.text('연결 종료'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: createViewer(watching: true),
    ));
    expect(find.byType(KyeobomViewerHomeAd), findsNothing);
  });

  testWidgets('station never imports a viewer advertising surface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KyeobomStationView(
        status: '연결 대기 중',
        streaming: false,
        microphoneOn: false,
        microphoneBusy: false,
        leaving: false,
        onLeave: () {},
        onToggleMicrophone: () {},
      ),
    ));
    expect(find.byType(KyeobomViewerHomeAd), findsNothing);
    expect(find.text('홈캠 대기 중'), findsOneWidget);
  });
}
