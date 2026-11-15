import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/main.dart';

void main() {
  testWidgets('Station start notice must be confirmed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RoleSelectionScreen()));

    expect(find.text('홈캠으로 사용'), findsOneWidget);
    expect(find.text('홈캠 보기'), findsOneWidget);

    await tester.tap(find.text('홈캠으로 사용'));
    await tester.pumpAndSettle();

    expect(find.text('홈캠 대기 모드가 시작됩니다.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(
          '충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('대기 시작'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('홈캠으로 사용'), findsOneWidget);
  });
}
