import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_station_start_dialog.dart';
import 'package:flutter_home_camera/kyeobom_design.dart';

void main() {
  Future<void> showPopup(WidgetTester tester, void Function(bool) report) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KyeobomTheme.light,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  final accepted = await showKyeobomStationStartDialog(context);
                  report(accepted);
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('standby popup keeps exact guidance and branded actions',
      (tester) async {
    bool? confirmed;
    await showPopup(tester, (value) => confirmed = value);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('홈캠 대기 모드가 시작됩니다.'), findsOneWidget);
    expect(
      find.text('화면은 어둡게 유지되며 자동으로 잠기지 않습니다.'),
      findsOneWidget,
    );
    expect(
      find.text(
        '안정적인 원격 연결을 위해 충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
      ),
      findsOneWidget,
    );
    expect(find.text('대기 시작'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);

    await tester.tap(find.text('대기 시작'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling standby popup does not start waiting',
      (tester) async {
    bool? confirmed;
    await showPopup(tester, (value) => confirmed = value);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.byType(Dialog), findsNothing);
  });
}
