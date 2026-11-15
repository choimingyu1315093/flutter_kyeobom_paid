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

  testWidgets('zoom controls clamp to 1x and reset to default', (tester) async {
    await pumpPreview(tester);

    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('0°'), findsOneWidget);

    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    await tester.tap(find.byTooltip('축소'));
    await tester.pump();
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    await tester.tap(find.byTooltip('회전 및 확대 초기화'));
    await tester.pump();
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('0°'), findsOneWidget);
  });

  testWidgets('rotate cycles 90 degrees and resets zoom', (tester) async {
    await pumpPreview(tester);

    await tester.tap(find.byTooltip('확대'));
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    await tester.tap(find.byTooltip('영상 90도 회전'));
    await tester.pump();
    expect(find.text('90°'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);

    await tester.tap(find.byTooltip('영상 90도 회전'));
    await tester.pump();
    expect(find.text('180°'), findsOneWidget);

    await tester.tap(find.byTooltip('회전 및 확대 초기화'));
    await tester.pump();
    expect(find.text('0°'), findsOneWidget);
  });
}
