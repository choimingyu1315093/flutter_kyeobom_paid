import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/device_health.dart';

void main() {
  testWidgets(
    'device health card is safe in an isolated widget test without Firebase',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DeviceHealthCard()),
        ),
      );

      expect(find.text('거치폰 상태 · 연결 정보 없음'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
