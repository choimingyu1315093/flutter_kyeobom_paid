import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/main.dart';

void main() {
  testWidgets('Viewer starts in portrait-style control layout without rotation button',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ViewerScreen()));

    expect(find.text('실시간 보기'), findsOneWidget);
    expect(find.text('가로 보기'), findsNothing);
    expect(find.text('자동 회전'), findsNothing);
    expect(find.byTooltip('영상 90도 회전'), findsNothing);
    expect(find.textContaining('가로 화면으로 전환됩니다'),
        findsOneWidget);
  });
}
