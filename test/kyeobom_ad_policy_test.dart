import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_ad_policy.dart';

void main() {
  test('non-mobile platforms never request ads', () {
    expect(KyeobomAdPolicy.isEnabled(
      platform: TargetPlatform.macOS, release: false), isFalse);
    expect(KyeobomAdPolicy.isEnabled(
      platform: TargetPlatform.windows, release: false), isFalse);
  });

  test('production is fail-closed until explicitly configured', () {
    expect(KyeobomAdPolicy.enableLiveAds, isFalse);
    expect(KyeobomAdPolicy.isEnabled(
      platform: TargetPlatform.android, release: true), isFalse);
    expect(KyeobomAdPolicy.isEnabled(
      platform: TargetPlatform.iOS, release: true), isFalse);
  });

  test('only official test ad units are used in QA', () {
    final androidBanner = KyeobomAdPolicy.unitId(
      platform: TargetPlatform.android,
      format: KyeobomAdFormat.banner, release: false,
    );
    final iosNative = KyeobomAdPolicy.unitId(
      platform: TargetPlatform.iOS,
      format: KyeobomAdFormat.native, release: false,
    );
    expect(androidBanner, contains('3940256099942544/'));
    expect(iosNative, contains('3940256099942544/'));
    expect(KyeobomAdPolicy.unitId(
      platform: TargetPlatform.macOS,
      format: KyeobomAdFormat.banner, release: false,
    ), isNull);
  });

  test('A-B assignment respects banner/native QA override', () {
    expect(KyeobomAdPolicy.choose(
      nativeAssigned: true, override: 'auto',
    ), KyeobomAdFormat.native);
    expect(KyeobomAdPolicy.choose(
      nativeAssigned: false, override: 'auto',
    ), KyeobomAdFormat.banner);
    expect(KyeobomAdPolicy.choose(
      nativeAssigned: false, override: 'native',
    ), KyeobomAdFormat.native);
    expect(KyeobomAdPolicy.choose(
      nativeAssigned: true, override: 'banner',
    ), KyeobomAdFormat.banner);
  });
}
