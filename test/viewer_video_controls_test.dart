import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/viewer_video_controls.dart';

void main() {
  Future<void> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 480,
              child: ViewerVideoControls(
                video: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('viewer retains 1x to 4x zoom and reset', (tester) async {
    await pumpPreview(tester);

    expect(find.text('1.0x'), findsOneWidget);
    expect(find.byTooltip('영상 90도 회전'), findsNothing);

    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    await tester.tap(find.byTooltip('축소'));
    await tester.pump();
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    await tester.tap(find.byTooltip('확대 초기화'));
    await tester.pump();
    expect(find.text('1.0x'), findsOneWidget);
  });

  testWidgets('zoom clamp disables minus at 1x and plus at 4x',
      (tester) async {
    await pumpPreview(tester);
    final minus = find.widgetWithIcon(IconButton, Icons.remove);
    final plus = find.widgetWithIcon(IconButton, Icons.add);

    expect(tester.widget<IconButton>(minus).onPressed, isNull);
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    expect(find.text('4.0x'), findsOneWidget);
    expect(tester.widget<IconButton>(plus).onPressed, isNull);
    expect(tester.widget<IconButton>(minus).onPressed, isNotNull);
  });
}
