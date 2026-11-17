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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: createViewer()));
    expect(find.byType(KyeobomViewerHomeAd), findsOneWidget);
    expect(find.text('실시간 보기'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNotNull);
    expect(scaffold.bottomNavigationBar.toString(),
        contains('SafeArea'));

    await tester.pumpWidget(
      MaterialApp(home: createViewer(busy: true)),
    );
    expect(find.byType(KyeobomViewerHomeAd), findsNothing);
  });

  testWidgets('sticky ad footer stays compact and camera CTA remains tappable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = false;

    // An in-memory ad preview keeps this deterministic and avoids invoking
    // the AdMob/UMP native SDK in tests. A tall banner + QA text reproduces
    // the actual layout that previously covered the entire viewer screen.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('켜봄')),
        body: Center(
          child: FilledButton(
            onPressed: () => tapped = true,
            child: const Text('실시간 보기'),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KyeobomAdFooterLayout(
                children: const [
                  Text('광고'),
                  SizedBox(
                    height: 132,
                    child: ColoredBox(color: Colors.black12),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('광고 QA · banner'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    final adRect = tester.getRect(find.byType(KyeobomAdFooterLayout));
    final buttonRect = tester.getRect(find.text('실시간 보기'));
    expect(adRect.height, lessThan(240),
        reason: 'An ad footer must not consume the full viewer height');
    expect(buttonRect.bottom, lessThan(adRect.top),
        reason: 'The live video button must remain above the ad footer');
    expect(find.text('켜봄'), findsOneWidget);

    await tester.tap(find.text('실시간 보기'));
    expect(tapped, isTrue);
  });

  testWidgets('compact viewer moves the ad into scroll instead of blocking CTA',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: createViewer()));
    expect(find.byType(KyeobomViewerHomeAd), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNull);
    expect(find.text('실시간 보기'), findsOneWidget);
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
