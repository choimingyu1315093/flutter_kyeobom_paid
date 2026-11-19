import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_screens.dart';

void main() {
  testWidgets('one live comparison button, absent in standby or normal builds',
      (tester) async {
    var taps = 0;
    Future<void> show({required bool live, bool qa = true,
        bool enabled = true, bool busy = false}) async {
      await tester.pumpWidget(MaterialApp(home: KyeobomStationView(
        status: '연결 대기 중', streaming: live,
        microphoneOn: false, microphoneBusy: false, leaving: false,
        onToggleMicrophone: () {}, onLeave: () {},
        nightCompareEnabled: enabled, nightCompareBusy: busy,
        onNightCompare: qa ? () { taps++; } : null,
      )));
    }
    final button = find.byKey(const ValueKey('nightComparisonQa'));
    await show(live: false);
    expect(button, findsNothing);
    await show(live: true, qa: false);
    expect(button, findsNothing);
    await show(live: true);
    expect(button, findsOneWidget);
    expect(find.text('비교: 유료 야간 보정 ON'), findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(taps, 1);
    await show(live: true, enabled: false);
    expect(find.text('비교: 기본 화질 OFF'), findsOneWidget);
    await show(live: true, busy: true);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
  });
}
