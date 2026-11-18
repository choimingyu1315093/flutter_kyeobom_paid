import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'kyeobom_design.dart';
import 'remote_control.dart';
import 'homecam_session_housekeeping.dart';
import 'kyeobom_station_start_dialog.dart';

class _AuthShell extends StatelessWidget {
  const _AuthShell({required this.child, this.showBack = false});
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack ? AppBar(
      leading: IconButton(
        tooltip: '뒤로',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
    ) : null,
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 32),
        child: child,
      ),
    ))),
  );
}

class _InputLabel extends StatelessWidget {
  const _InputLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(text, style: const TextStyle(
      fontSize: 12, color: KyeobomPalette.ink,
      fontWeight: FontWeight.w700,
    )),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool hidePassword = true;
  String? error;

  Future<void> _submit() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await RemoteControl.instance.signIn(
        email.text.trim(), password.text, register: false,
      );
      unawaited(HomeCamSessionHousekeeping.runIfDue());
      if (mounted) Navigator.of(context).pushReplacementNamed('/roles');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? '로그인 정보를 확인해 주세요.');
    } catch (e) {
      if (mounted) setState(() => error = '로그인 오류: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _startStation() async {
    if (busy) return;
    final approved = await showKyeobomStationStartDialog(context);
    if (approved != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] iOS/Android station: anonymous sign-in begin');
      }
      await RemoteControl.instance.signInStationAnonymously();
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] station: anonymous sign-in success; navigate');
      }
      if (mounted) Navigator.of(context).pushReplacementNamed('/station');
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] station anonymous sign-in error: $e');
        debugPrintStack(stackTrace: stack);
      }
      if (mounted) setState(() => error =
          '거치폰 설정 오류: $e. Firebase Authentication의 익명 로그인을 활성화해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _AuthShell(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      const Center(child: KyeobomMark(size: 74)),
      const SizedBox(height: 17),
      const Center(child: Text('켜봄', style: TextStyle(
        color: KyeobomPalette.navy, fontWeight: FontWeight.w900,
        fontSize: 27, letterSpacing: -1))),
      const SizedBox(height: 7),
      const Center(child: Text('우리 집을 확인하는 가장 간편한 방법',
        style: TextStyle(fontSize: 12, color: KyeobomPalette.muted))),
      const SizedBox(height: 11),
      const Center(child: KyeobomEyebrow('우리 집을 언제 어디서나')),
      const SizedBox(height: 46),
      const _InputLabel('이메일 주소'),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(hintText: 'example@gmail.com'),
      ),
      const SizedBox(height: 19),
      const _InputLabel('비밀번호'),
      TextField(
        controller: password,
        obscureText: hidePassword,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: '비밀번호를 입력해 주세요',
          suffixIcon: IconButton(
            tooltip: hidePassword ? '비밀번호 보기' : '비밀번호 숨기기',
            onPressed: () => setState(() => hidePassword = !hidePassword),
            icon: Icon(hidePassword
                ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: 13),
        Text(error!, style: const TextStyle(
          color: Color(0xFFB54349), fontSize: 12)),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy ? null : _submit,
        child: Text(busy ? '로그인 중...' : '로그인'),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
          ),
          child: const Text('회원가입', style: TextStyle(
            fontSize: 12, color: KyeobomPalette.muted)),
        ),
        const Text(' | ', style: TextStyle(color: KyeobomPalette.border)),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PasswordResetScreen()),
          ),
          child: const Text('비밀번호 찾기', style: TextStyle(
            fontSize: 12, color: KyeobomPalette.muted)),
        ),
      ]),
      const SizedBox(height: 7),
      const Divider(height: 28),
      OutlinedButton.icon(
        onPressed: busy ? null : _startStation,
        icon: const Icon(Icons.videocam_outlined),
        label: const Text('이 스마트폰을 거치폰으로 설정'),
      ),
      const SizedBox(height: 9),
      const Center(child: Text(
        '뷰어폰은 이메일로 로그인하고, 거치폰은 별도 인증으로 연결합니다.\n'
        '거치폰 화면에 표시되는 코드를 뷰어폰에 입력한 뒤 승인해 주세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: KyeobomPalette.muted,
          fontSize: 11, height: 1.5),
      )),
    ]),
  );
}

/// Mirrors the Figma registration screen without inventing a published
/// service agreement. Account creation reuses existing Firebase Auth.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool acceptedTestNotice = false;
  bool busy = false;
  String? error;

  Future<void> _submit() async {
    if (busy) return;
    if (password.text != confirmation.text) {
      setState(() => error = '비밀번호가 일치하지 않아요.');
      return;
    }
    if (!acceptedTestNotice) {
      setState(() => error = '테스트 계정 안내를 확인해 주세요.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await RemoteControl.instance.signIn(
        email.text.trim(), password.text, register: true,
      );
      unawaited(HomeCamSessionHousekeeping.runIfDue());
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/roles', (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      // Do not log the email or password. Show the SDK error code in debug,
      // so Auth emulator transport failures are diagnosable on physical phones.
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] Auth signup failed '
            '[firebase_auth/${e.code}]: ${e.message}');
      }
      if (mounted) {
        setState(() => error = kDebugMode
            ? '테스트 회원가입 오류 [${e.code}]: ${e.message ?? "상세 메시지 없음"}'
            : e.message ?? '계정을 만들 수 없어요.');
      }
    } catch (e) {
      if (mounted) setState(() => error = '회원가입 오류: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose(); password.dispose(); confirmation.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthShell(
    showBack: true,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const KyeobomEyebrow('JOIN KYEOBOM'),
      const SizedBox(height: 13),
      const Text('간편하게 가입하고\n바로 연결해 보세요',
        style: TextStyle(color: KyeobomPalette.ink, fontSize: 26,
          height: 1.25, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('이메일과 비밀번호만 있으면 시작할 수 있어요.',
        style: TextStyle(color: KyeobomPalette.muted, fontSize: 12)),
      const SizedBox(height: 27),
      const _InputLabel('이메일 주소'),
      TextField(controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(hintText: 'example@gmail.com')),
      const SizedBox(height: 16),
      const _InputLabel('비밀번호'),
      TextField(controller: password, obscureText: true,
        decoration: const InputDecoration(hintText: '비밀번호 6자 이상')),
      const SizedBox(height: 16),
      const _InputLabel('비밀번호 확인'),
      TextField(controller: confirmation, obscureText: true,
        decoration: const InputDecoration(hintText: '비밀번호 다시 입력')),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: KyeobomPalette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
          value: acceptedTestNotice,
          contentPadding: EdgeInsets.zero,
          title: const Text('테스트 계정 안내 확인',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: const Text('현재 두 기기는 동일한 계정으로 연결하는 테스트 버전입니다.',
            style: TextStyle(fontSize: 11, color: KyeobomPalette.muted)),
            onChanged: (v) => setState(() => acceptedTestNotice = v ?? false),
          ),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: const TextStyle(
          color: Color(0xFFB54349), fontSize: 12)),
      ],
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: busy ? null : _submit,
        child: Text(busy ? '계정 생성 중...' : '계정 만들기'),
      )),
    ]),
  );
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final email = TextEditingController();
  bool busy = false;
  String? message;

  Future<void> _send() async {
    if (busy) return;
    if (email.text.trim().isEmpty) {
      setState(() => message = '이메일 주소를 입력해 주세요.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) {
        setState(() => message =
            '메일이 발송 가능한 계정이라면 재설정 링크가 전달됩니다. 메일함을 확인해 주세요.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = e.message ?? '메일 발송에 실패했어요.');
    } catch (e) {
      if (mounted) setState(() => message = '요청 오류: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() { email.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _AuthShell(
    showBack: true,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const KyeobomEyebrow('RESET PASSWORD'),
      const SizedBox(height: 13),
      const Text('비밀번호를\n잊으셨나요?',
        style: TextStyle(color: KyeobomPalette.ink,
          fontSize: 26, fontWeight: FontWeight.w800, height: 1.25)),
      const SizedBox(height: 10),
      const Text('가입한 이메일로 비밀번호 재설정 링크를 보내드릴게요.',
        style: TextStyle(color: KyeobomPalette.muted, fontSize: 12)),
      const SizedBox(height: 31),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KyeobomPalette.bluePale,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Row(children: [
          Icon(Icons.lock_reset_rounded,
            color: KyeobomPalette.blue, size: 24),
          SizedBox(width: 12),
          Expanded(child: Text(
            '이메일 주소를 입력하면 비밀번호를 다시 설정할 수 있어요.',
            style: TextStyle(fontSize: 12, color: KyeobomPalette.ink),
          )),
        ]),
      ),
      const SizedBox(height: 25),
      const _InputLabel('이메일 주소'),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(hintText: 'example@gmail.com')),
      if (message != null) ...[
        const SizedBox(height: 15),
        Text(message!, style: const TextStyle(
          color: KyeobomPalette.muted, fontSize: 12)),
      ],
      const SizedBox(height: 22),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: busy ? null : _send,
        child: Text(busy ? '발송 중...' : '비밀번호 재설정 메일 받기'),
      )),
      const SizedBox(height: 12),
      Center(child: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('로그인으로 돌아가기'),
      )),
    ]),
  );
}
