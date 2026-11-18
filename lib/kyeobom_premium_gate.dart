import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'kyeobom_billing_controller.dart';
import 'kyeobom_subscription_screen.dart';

/// Reusable premium-only entry gate. DO NOT wrap the free camera viewer or
/// device overheat protection. The server must also enforce entitlement
/// on every protected premium data path / callable.
class KyeobomPremiumGate extends StatelessWidget {
  const KyeobomPremiumGate({
    super.key,
    required this.premiumBuilder,
    required this.featureName,
  });

  final WidgetBuilder premiumBuilder;
  final String featureName;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return _PaywallEntry(featureName: featureName,
        explanation: '프리미엄 기능은 뷰어 이메일 계정으로 로그인해야 해요.');
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
        .collection('homecamEntitlements').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _PaywallEntry(featureName: featureName,
            explanation: '유료 권한을 확인하지 못해 기능을 잠시 잠갔어요. '
              '인터넷과 구독 상태를 확인해 주세요.');
        }
        if (KyeobomPremiumEntitlement.active(snapshot.data?.data())) {
          return premiumBuilder(context);
        }
        return _PaywallEntry(featureName: featureName,
          explanation: '이 기능은 서버에서 검증된 구독에만 제공돼요.');
      },
    );
  }
}

class _PaywallEntry extends StatelessWidget {
  const _PaywallEntry({required this.featureName, required this.explanation});
  final String featureName;
  final String explanation;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(featureName)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 14),
                Text(explanation, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const KyeobomSubscriptionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('프리미엄 구독 확인'),
                ),
                const SizedBox(height: 14),
                const Text(
                  '실시간 홈캠 보기와 QR 연결은 구독 없이 이용할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
