import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/kyeobom_ad_frequency.dart';

void main() {
  final now = DateTime(2026, 11, 15, 20, 30);

  test('interstitial never appears before or during live viewing', () {
    const duration = Duration(minutes: 3);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: false,
      userStoppedVideo: true,
      appForeground: true,
      completedViews: 50,
      viewedFor: duration,
      fullscreenToday: 0,
      now: now,
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true,
      userStoppedVideo: false,
      appForeground: true,
      completedViews: 50,
      viewedFor: duration,
      fullscreenToday: 0,
      now: now,
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true,
      userStoppedVideo: true,
      appForeground: false,
      completedViews: 50,
      viewedFor: duration,
      fullscreenToday: 0,
      now: now,
    ), isFalse);
  });

  test('interstitial requires 3 completed views and at least 15s viewing', () {
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 2, viewedFor: const Duration(minutes: 5),
      fullscreenToday: 0, now: now,
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 3, viewedFor: const Duration(seconds: 3),
      fullscreenToday: 0, now: now,
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 3, viewedFor: const Duration(seconds: 30),
      fullscreenToday: 0, now: now,
    ), isTrue);
  });

  test('interstitial honors shared daily cap and fullscreen cooldown', () {
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 10, viewedFor: const Duration(minutes: 3),
      fullscreenToday: 1, now: now,
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 10, viewedFor: const Duration(minutes: 3),
      fullscreenToday: 0, now: now,
      lastFullscreenAt: now.subtract(const Duration(hours: 2)),
    ), isFalse);
    expect(KyeobomAdFrequency.canInterstitial(
      viewerHome: true, userStoppedVideo: true, appForeground: true,
      completedViews: 10, viewedFor: const Duration(minutes: 3),
      fullscreenToday: 0, now: now,
      lastFullscreenAt: now.subtract(const Duration(hours: 7)),
    ), isTrue);
  });

  test('app opening is warm viewer-home return only after 10 minutes', () {
    const timeAway = Duration(minutes: 15);
    bool eligible({bool home = true, bool warm = true, bool foreground = true,
      int views = 5, Duration away = timeAway, int today = 0}) =>
      KyeobomAdFrequency.canAppOpen(
        viewerHome: home, warmReturn: warm, appForeground: foreground,
        completedViews: views, backgroundFor: away,
        fullscreenToday: today, now: now);
    expect(eligible(home: false), isFalse);
    expect(eligible(warm: false), isFalse);
    expect(eligible(foreground: false), isFalse);
    expect(eligible(views: 1), isFalse);
    expect(eligible(away: const Duration(minutes: 1)), isFalse);
    expect(eligible(today: 1), isFalse);
    expect(eligible(), isTrue);
    expect(KyeobomAdFrequency.canAppOpen(
      viewerHome: true, warmReturn: true, appForeground: true,
      completedViews: 20, backgroundFor: timeAway, fullscreenToday: 0,
      now: now, lastFullscreenAt: now.subtract(const Duration(hours: 12)),
    ), isFalse);
  });

  test('app-open cached ad expires after 4 hours', () {
    expect(KyeobomAdFrequency.validCachedAppOpen(
      now.subtract(const Duration(minutes: 30)), now), isTrue);
    expect(KyeobomAdFrequency.validCachedAppOpen(
      now.subtract(const Duration(hours: 4)), now), isFalse);
    expect(KyeobomAdFrequency.validCachedAppOpen(
      now.add(const Duration(seconds: 10)), now), isFalse);
  });

  test('reward is strictly optional and never needed for the camera', () {
    expect(KyeobomAdFrequency.rewardDuration,
        const Duration(hours: 12));
    expect(KyeobomAdFrequency.maxFullscreenPerDay, 1);
  });
}
