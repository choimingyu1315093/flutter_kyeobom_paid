import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_ad_policy.dart';

void main() {
  test('all ten owner-issued production AdMob ad-unit IDs match their platform',
      () {
    const expected = <TargetPlatform, Map<KyeobomAdFormat, String>>{
      TargetPlatform.android: {
        KyeobomAdFormat.banner: 'ca-app-pub-5893975529562336/6414884933',
        KyeobomAdFormat.native: 'ca-app-pub-5893975529562336/2426317273',
        KyeobomAdFormat.interstitial: 'ca-app-pub-5893975529562336/2290585905',
        KyeobomAdFormat.appOpen: 'ca-app-pub-5893975529562336/2085078484',
        KyeobomAdFormat.rewarded: 'ca-app-pub-5893975529562336/6343887693',
      },
      TargetPlatform.iOS: {
        KyeobomAdFormat.banner: 'ca-app-pub-5893975529562336/6152316006',
        KyeobomAdFormat.native: 'ca-app-pub-5893975529562336/4638768834',
        KyeobomAdFormat.interstitial: 'ca-app-pub-5893975529562336/5599275527',
        KyeobomAdFormat.appOpen: 'ca-app-pub-5893975529562336/4647662645',
        KyeobomAdFormat.rewarded: 'ca-app-pub-5893975529562336/5529499473',
      },
    };

    final seen = <String>{};
    for (final platform in expected.keys) {
      for (final entry in expected[platform]!.entries) {
        final unit = KyeobomAdPolicy.productionUnit(
          platform: platform,
          format: entry.key,
        );
        expect(unit, entry.value,
            reason: 'Incorrect ${platform.name} ${entry.key.name} ad unit');
        expect(unit, matches(RegExp(
          r'^ca-app-pub-5893975529562336/[0-9]{10}$',
        )));
        expect(seen.add(unit!), isTrue, reason: 'Ad unit IDs must be unique');
      }
    }
    expect(seen.length, 10);
  });

  test('QA always uses Google demo ad IDs, not the newly linked live IDs', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final format in KyeobomAdFormat.values) {
        final qa = KyeobomAdPolicy.unitId(
          platform: platform, format: format, release: false,
        );
        expect(qa, startsWith('ca-app-pub-3940256099942544/'));
        expect(qa, isNot(KyeobomAdPolicy.productionUnit(
          platform: platform, format: format,
        )));
      }
    }
  });

  test('both real app IDs are distinct and match owner ad unit IDs', () {
    expect(KyeobomAdPolicy.androidAppId,
        'ca-app-pub-5893975529562336~4819053037');
    expect(KyeobomAdPolicy.iosAppId,
        'ca-app-pub-5893975529562336~6718137266');
    expect(KyeobomAdPolicy.androidAppId,
        isNot(KyeobomAdPolicy.iosAppId));
    const ownerPrefix = 'ca-app-pub-5893975529562336';
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final appId = platform == TargetPlatform.android
          ? KyeobomAdPolicy.androidAppId
          : KyeobomAdPolicy.iosAppId;
      expect(appId, startsWith('$ownerPrefix~'));
      for (final format in KyeobomAdFormat.values) {
        final adId = KyeobomAdPolicy.productionUnit(
          platform: platform, format: format,
        );
        expect(adId, startsWith('$ownerPrefix/'));
      }
    }
  });

  test('release remains opt-in even with real app and ad unit IDs', () {
    expect(KyeobomAdPolicy.enableLiveAds, isFalse);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(KyeobomAdPolicy.isEnabled(
        platform: platform, release: true,
      ), isFalse);
      for (final format in KyeobomAdFormat.values) {
        expect(KyeobomAdPolicy.unitId(
          platform: platform, format: format, release: true,
        ), isNull);
      }
    }
  });
}
