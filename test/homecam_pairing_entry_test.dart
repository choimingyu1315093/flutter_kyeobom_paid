import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('station owner has an explicit pairing and revocation entry',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: KyeobomStationView(
        status: '연결 대기 중',
        streaming: false,
        microphoneOn: false,
        microphoneBusy: false,
        leaving: false,
        onLeave: () {},
        onToggleMicrophone: () {},
        onManagePairing: () => opened++,
      ),
    ));
    expect(find.text('기기 연결·권한 관리'), findsOneWidget);
    await tester.tap(find.text('기기 연결·권한 관리'));
    expect(opened, 1);
  });
}
