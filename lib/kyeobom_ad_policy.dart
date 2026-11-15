import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ads are intentionally allowed ONLY on the viewer home dashboard.
/// No ads on station standby, in live video, or before starting a stream.
enum KyeobomAdFormat { native, banner }

abstract final class KyeobomAdPolicy {
  static const bool enableLiveAds =
      bool.fromEnvironment('KYEOBOM_ENABLE_LIVE_ADS', defaultValue: false);
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

  static const String _demoPrefix = 'ca-app-pub-3940256099942544';
  static const String _androidBannerDemo =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _androidNativeDemo =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _iosBannerDemo =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _iosNativeDemo =
      'ca-app-pub-3940256099942544/3986624511';

  static bool _valid(String text, {required bool appId}) {
    if (text.isEmpty || text.startsWith(_demoPrefix)) return false;
    return appId
        ? RegExp(r'^ca-app-pub-\\d{16}~\\d{10}$').hasMatch(text)
        : RegExp(r'^ca-app-pub-\\d{16}/\\d{10}$').hasMatch(text);
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
      (TargetPlatform.iOS, KyeobomAdFormat.banner) => iosBanner,
      (TargetPlatform.iOS, KyeobomAdFormat.native) => iosNative,
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
      (TargetPlatform.iOS, KyeobomAdFormat.banner) => _iosBannerDemo,
      (TargetPlatform.iOS, KyeobomAdFormat.native) => _iosNativeDemo,
      _ => null,
    };
  }

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
