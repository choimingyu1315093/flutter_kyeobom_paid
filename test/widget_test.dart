import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/main.dart';

void main() {
  testWidgets('Home Camera role selection screen renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));
    expect(find.text('이 기기의 역할을 선택하세요'), findsOneWidget);
    expect(find.text('거치폰 · 카메라 대기'), findsOneWidget);
    expect(find.text('뷰어폰 · 실시간 보기'), findsOneWidget);
  });
}
