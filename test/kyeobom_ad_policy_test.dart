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

  test('iOS native stays isolated until explicit policy QA opt-in', () {
    expect(KyeobomAdPolicy.nativeAllowed(TargetPlatform.android), isTrue);
    expect(KyeobomAdPolicy.nativeAllowed(TargetPlatform.iOS),
        kDebugMode && KyeobomAdPolicy.enableIosNative);
    expect(KyeobomAdPolicy.enableIosNative, isFalse);
    expect(KyeobomAdPolicy.qaAdsDisabled, isFalse);
  });

  test('standard 320x50 home banner does not overflow narrow viewports', () {
    // Home uses 20dp outer padding on each side plus a 1dp card border.
    expect(KyeobomAdPolicy.canFitHomeAd(320), isFalse);
    expect(KyeobomAdPolicy.canFitHomeAd(360), isFalse);
    expect(KyeobomAdPolicy.canFitHomeAd(362), isTrue);
    expect(KyeobomAdPolicy.canFitHomeAd(375), isTrue);
    expect(KyeobomAdPolicy.canFitHomeAd(390), isTrue);
  });

  test('iOS native QA uses scroll not sticky viewport footer', () {
    expect(KyeobomAdPolicy.useStickyHomeAd(
      screenHeight: 844, iosNativeDiagnostic: false,
    ), isTrue);
    expect(KyeobomAdPolicy.useStickyHomeAd(
      screenHeight: 844, iosNativeDiagnostic: true,
    ), isFalse);
    expect(KyeobomAdPolicy.useStickyHomeAd(
      screenHeight: 640, iosNativeDiagnostic: false,
    ), isFalse);
    expect(KyeobomAdPolicy.iosNativeQa, isFalse);
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
  test('fullscreen ads remain opt-in and official QA IDs are provided', () {
    expect(KyeobomAdPolicy.enableAppOpen, isFalse);
    expect(KyeobomAdPolicy.enableInterstitial, isFalse);
    expect(KyeobomAdPolicy.enableRewarded, isFalse);
    for (final type in [
      KyeobomAdFormat.appOpen,
      KyeobomAdFormat.interstitial,
      KyeobomAdFormat.rewarded,
    ]) {
      expect(KyeobomAdPolicy.formatEnabled(type), isFalse);
      expect(KyeobomAdPolicy.unitId(
        platform: TargetPlatform.android, format: type, release: false,
      ), startsWith('ca-app-pub-3940256099942544/'));
      expect(KyeobomAdPolicy.unitId(
        platform: TargetPlatform.iOS, format: type, release: false,
      ), startsWith('ca-app-pub-3940256099942544/'));
    }
  });

}
