import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_pairing_screens.dart';

void main() {
  testWidgets('approval advances to viewer without Future-valued setState',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ViewerPairingGate(
        accessCheck: () async => false,
        viewerBuilder: (_) => const Scaffold(
          body: Center(child: Text('VIEWER_READY')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final screen = tester.widget<ViewerPairingScreen>(
      find.byType(ViewerPairingScreen),
    );
    // Simulate the existing Firestore approval listener's callback after it
    // has already saved the validated station->viewer grant.
    screen.onPaired();
    await tester.pumpAndSettle();
    expect(find.text('VIEWER_READY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
