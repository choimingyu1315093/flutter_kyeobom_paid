import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ads are intentionally allowed ONLY on the viewer home dashboard.
/// No ads on station standby, in live video, or before starting a stream.
enum KyeobomAdFormat { native, banner, appOpen, interstitial, rewarded }

abstract final class KyeobomAdPolicy {
  static const bool enableLiveAds =
      bool.fromEnvironment('KYEOBOM_ENABLE_LIVE_ADS', defaultValue: false);
  // Separate experimental gates. Live-video entry NEVER requires an ad.
  static const enableAppOpen =
      bool.fromEnvironment('KYEOBOM_ENABLE_APP_OPEN_ADS', defaultValue: false);
  static const enableInterstitial =
      bool.fromEnvironment('KYEOBOM_ENABLE_INTERSTITIAL_ADS', defaultValue: false);
  static const enableRewarded =
      bool.fromEnvironment('KYEOBOM_ENABLE_REWARDED_ADS', defaultValue: false);

  static const String formatOverride =
      String.fromEnvironment('KYEOBOM_AD_FORMAT', defaultValue: 'auto');

  static const String androidAppId =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_APP_ID');
  static const String iosAppId =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_APP_ID');
  static const String androidBanner =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_BANNER_ID');
  static const String androidNative =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_NATIVE_ID');
  static const String iosBanner =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_BANNER_ID');
  static const String iosNative =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_NATIVE_ID');
  static const String androidAppOpen =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_APP_OPEN_ID');
  static const String iosAppOpen =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_APP_OPEN_ID');
  static const String androidInterstitial =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_INTERSTITIAL_ID');
  static const String iosInterstitial =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_INTERSTITIAL_ID');
  static const String androidRewarded =
      String.fromEnvironment('KYEOBOM_ANDROID_ADMOB_REWARDED_ID');
  static const String iosRewarded =
      String.fromEnvironment('KYEOBOM_IOS_ADMOB_REWARDED_ID');

  static const String _demoPrefix = 'ca-app-pub-3940256099942544';
  static const String _androidBannerDemo =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _androidNativeDemo =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _iosBannerDemo =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _iosNativeDemo =
      'ca-app-pub-3940256099942544/3986624511';
  static const String _androidAppOpenDemo =
      'ca-app-pub-3940256099942544/9257395921';
  static const String _iosAppOpenDemo =
      'ca-app-pub-3940256099942544/5575463023';
  static const String _androidInterstitialDemo =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosInterstitialDemo =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _androidRewardedDemo =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosRewardedDemo =
      'ca-app-pub-3940256099942544/1712485313';

  static bool _valid(String text, {required bool appId}) {
    if (text.isEmpty || text.startsWith(_demoPrefix)) return false;
    return appId
        ? RegExp(r'^ca-app-pub-[0-9]{16}~[0-9]{10}$').hasMatch(text)
        : RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}$').hasMatch(text);
  }

  static bool supportsPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  static bool isEnabled({
    required TargetPlatform platform,
    required bool release,
  }) {
    if (!supportsPlatform(platform)) return false;
    if (!release) return true; // Google demo units ONLY for QA builds.
    if (!enableLiveAds) return false; // Explicit production opt-in.
    return _valid(
          platform == TargetPlatform.android ? androidAppId : iosAppId,
          appId: true,
        ) &&
        (productionUnit(
          platform: platform, format: KyeobomAdFormat.banner,
        ) != null ||
        productionUnit(
          platform: platform, format: KyeobomAdFormat.native,
        ) != null);
  }

  static String? productionUnit({
    required TargetPlatform platform,
    required KyeobomAdFormat format,
  }) {
    final value = switch ((platform, format)) {
      (TargetPlatform.android, KyeobomAdFormat.banner) => androidBanner,
      (TargetPlatform.android, KyeobomAdFormat.native) => androidNative,
      (TargetPlatform.android, KyeobomAdFormat.appOpen) => androidAppOpen,
      (TargetPlatform.android, KyeobomAdFormat.interstitial) => androidInterstitial,
      (TargetPlatform.android, KyeobomAdFormat.rewarded) => androidRewarded,
      (TargetPlatform.iOS, KyeobomAdFormat.banner) => iosBanner,
      (TargetPlatform.iOS, KyeobomAdFormat.native) => iosNative,
      (TargetPlatform.iOS, KyeobomAdFormat.appOpen) => iosAppOpen,
      (TargetPlatform.iOS, KyeobomAdFormat.interstitial) => iosInterstitial,
      (TargetPlatform.iOS, KyeobomAdFormat.rewarded) => iosRewarded,
      _ => '',
    };
    return _valid(value, appId: false) ? value : null;
  }

  static String? unitId({
    required TargetPlatform platform,
    required KyeobomAdFormat format,
    required bool release,
  }) {
    if (!isEnabled(platform: platform, release: release)) return null;
    if (release) return productionUnit(platform: platform, format: format);
    return switch ((platform, format)) {
      (TargetPlatform.android, KyeobomAdFormat.banner) => _androidBannerDemo,
      (TargetPlatform.android, KyeobomAdFormat.native) => _androidNativeDemo,
      (TargetPlatform.android, KyeobomAdFormat.appOpen) => _androidAppOpenDemo,
      (TargetPlatform.android, KyeobomAdFormat.interstitial) =>
          _androidInterstitialDemo,
      (TargetPlatform.android, KyeobomAdFormat.rewarded) => _androidRewardedDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.banner) => _iosBannerDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.native) => _iosNativeDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.appOpen) => _iosAppOpenDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.interstitial) => _iosInterstitialDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.rewarded) => _iosRewardedDemo,
      _ => null,
    };
  }

  /// All full-screen placements must be explicitly enabled. This check does
  /// not grant consent: the caller must also verify UMP canRequestAds().
  static bool formatEnabled(KyeobomAdFormat format) => switch (format) {
    KyeobomAdFormat.appOpen => enableAppOpen,
    KyeobomAdFormat.interstitial => enableInterstitial,
    KyeobomAdFormat.rewarded => enableRewarded,
    _ => true,
  };

  static KyeobomAdFormat choose({
    required bool nativeAssigned,
    required String override,
  }) {
    if (override == 'native') return KyeobomAdFormat.native;
    if (override == 'banner') return KyeobomAdFormat.banner;
    return nativeAssigned
        ? KyeobomAdFormat.native
        : KyeobomAdFormat.banner;
  }

  /// Stable 50/50 assignment per installation. No Firebase writes,
  /// personal identifier or tracking beyond this device's preferences.
  static Future<KyeobomAdFormat> assignedFormat() async {
    if (formatOverride == 'banner' || formatOverride == 'native') {
      return choose(nativeAssigned: false, override: formatOverride);
    }
    try {
      final prefs = SharedPreferencesAsync();
      const key = 'kyeobom_ad_format_experiment_v1';
      var assigned = await prefs.getString(key);
      if (assigned != 'banner' && assigned != 'native') {
        assigned = Random.secure().nextBool() ? 'native' : 'banner';
        await prefs.setString(key, assigned);
      }
      return assigned == 'native'
          ? KyeobomAdFormat.native
          : KyeobomAdFormat.banner;
    } catch (_) {
      // Ad selection failure must never affect the camera.
      return KyeobomAdFormat.banner;
    }
  }
}
