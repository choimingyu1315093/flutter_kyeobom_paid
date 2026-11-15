import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_auth_screens.dart';

void main() {
  testWidgets('login exposes Figma navigation to signup and password reset',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('켜봄'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    expect(find.text('비밀번호 찾기'), findsOneWidget);
    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('계정 만들기'), findsOneWidget);
    expect(find.text('테스트 계정 안내 확인'), findsOneWidget);
  });

  testWidgets('password reset is a separate screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('비밀번호 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 재설정 메일 받기'), findsOneWidget);
    expect(find.text('로그인으로 돌아가기'), findsOneWidget);
  });
}
