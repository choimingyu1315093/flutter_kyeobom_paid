import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/device_health.dart';

void main() {
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
