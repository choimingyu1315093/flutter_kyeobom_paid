import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/device_health.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('station shows warning without hiding existing controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: const _HealthStationTestView(),
    ));
    expect(find.textContaining('기기 상태'), findsOneWidget);
    expect(find.textContaining('발열이 높'), findsOneWidget);
    expect(find.text('대기 종료'), findsOneWidget);
  });

  testWidgets(
    'health card stays compact and safe without Firebase',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DeviceHealthCard())),
      );

      expect(find.text('홈캠 상태'), findsOneWidget);
      expect(find.text('연결 정보 없음'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _HealthStationTestView extends StatelessWidget {
  const _HealthStationTestView();

  @override
  Widget build(BuildContext context) => KyeobomStationView(
    status: '연결 대기 중',
    streaming: false,
    microphoneOn: false,
    microphoneBusy: false,
    leaving: false,
    healthSummary: '기기 상태 · 배터리 70% · 발열 높음',
    healthWarning: '발열이 높아 영상 품질을 낮춥니다.',
    onLeave: () {},
    onToggleMicrophone: () {},
  );
}
