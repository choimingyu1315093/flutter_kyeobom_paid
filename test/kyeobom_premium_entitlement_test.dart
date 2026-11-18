import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_billing_controller.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18);
  test('server-certified unexpired entitlement enables premium UI', () {
    expect(KyeobomPremiumEntitlement.active({
      'source': 'google_play',
      'isActive': true,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
    }, now: now), isTrue);
  });
  test('free or missing entitlement never enables premium', () {
    expect(KyeobomPremiumEntitlement.active(null, now: now), isFalse);
    expect(KyeobomPremiumEntitlement.active({
      'source': 'google_play',
      'isActive': false,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
    }, now: now), isFalse);
  });
  test('expired or non-Google entitlement is locked', () {
    expect(KyeobomPremiumEntitlement.active({
      'source': 'google_play',
      'isActive': true,
      'expiresAt': Timestamp.fromDate(now.subtract(const Duration(seconds: 1))),
    }, now: now), isFalse);
    expect(KyeobomPremiumEntitlement.active({
      'source': 'client',
      'isActive': true,
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
    }, now: now), isFalse);
  });
}
