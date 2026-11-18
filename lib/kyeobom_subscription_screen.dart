import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kyeobom_billing_controller.dart';

class KyeobomSubscriptionScreen extends StatefulWidget {
  const KyeobomSubscriptionScreen({super.key});

  @override
  State<KyeobomSubscriptionScreen> createState() =>
      _KyeobomSubscriptionScreenState();
}

class _KyeobomSubscriptionScreenState
    extends State<KyeobomSubscriptionScreen> {
  // QA flag: never charge anyone before product setup, legal pages and
  // backend subscription verification have been validated on internal track.
  static const _qaPurchasesEnabled =
      bool.fromEnvironment('KYEOBOM_ENABLE_ANDROID_IAP_QA');
  late final KyeobomBillingController _billing;

  @override
  void initState() {
    super.initState();
    _billing = KyeobomBillingController();
    unawaited(_billing.initialize());
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  Future<void> _manage() async {
    final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Google Play 구독 관리 화면을 열 수 없어요.'),
      ));
    }
  }

  String _displayName(String id) {
    return switch (id) {
      KyeobomSubscriptionProducts.monthly => '월간 구독',
      KyeobomSubscriptionProducts.yearly => '연간 구독',
      _ => id,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('켜봄 프리미엄')),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _billing,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 54),
            const SizedBox(height: 16),
            const Text('우리 집을 더 편리하게',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              '무료 실시간 보기·QR 연결은 그대로 사용할 수 있어요. '
              '프리미엄 자동화 기능은 개발·검증 완료 후 제공할 예정입니다.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('프리미엄 제공 예정 기능',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 9),
                  Text('• 이벤트 자동 녹화와 기록 확인'),
                  Text('• 아기 울음·소리 변화 감지'),
                  Text('• 저조도 영상 개선'),
                ],
              ),
            )),
            const SizedBox(height: 16),
            if (_billing.premium)
              const Card(child: ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Google Play 구독 인증 완료'),
                subtitle: Text('유료 권한이 Firebase에서 확인됐어요.'),
              )),
            if (_billing.loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              )),
            if (!Platform.isAndroid)
              const Card(child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('iPhone 구독은 준비 중이에요'),
                subtitle: Text('현재는 Android Google Play부터 개발합니다.'),
              )),
            for (final product in _billing.products) Card(
              key: Key('kyeobom-subscription-' + product.id),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_displayName(product.id),
                      style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(product.price,
                      style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Google Play가 표시하는 실제 가격으로 결제되며 '
                      '해지하기 전까지 자동 갱신됩니다.',
                      style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _qaPurchasesEnabled && _billing.canPurchase
                          && !_billing.premium
                          ? () => _billing.buy(product) : null,
                      child: Text(_qaPurchasesEnabled
                          ? 'Google Play에서 구독하기'
                          : '내부 결제 QA 준비 중'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_billing.status, textAlign: TextAlign.center),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: Platform.isAndroid && _qaPurchasesEnabled
                  ? () => _billing.restore() : null,
              icon: const Icon(Icons.restore),
              label: const Text('구매 복원'),
            ),
            TextButton(
              onPressed: Platform.isAndroid ? _manage : null,
              child: const Text('Google Play 구독 관리 및 해지'),
            ),
            const SizedBox(height: 12),
            const Text(
              '계정 삭제만으로 구독이 해지되지는 않습니다. '
              '환불 및 해지는 Google Play 구독 관리에서 확인해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              FirebaseAuth.instance.currentUser?.isAnonymous == true
                ? '결제는 뷰어 이메일 계정에서만 가능합니다.'
                : '현재 계정으로 구독 권한을 확인합니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
