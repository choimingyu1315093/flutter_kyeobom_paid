import 'package:shared_preferences/shared_preferences.dart';

/// Pure rules, shared across app-open and interstitial formats.
/// A pending video start, streaming session, station role and app exit always
/// override eligibility; no fullscreen ad may delay the core camera action.
abstract final class KyeobomAdFrequency {
  static const minViewDuration = Duration(seconds: 15);
  static const minAppOpenBackground = Duration(minutes: 10);
  static const minBetweenFullscreen = Duration(hours: 6);
  static const minBetweenAppOpens = Duration(hours: 24);
  static const maxFullscreenPerDay = 1;
  static const minInterstitialViews = 3;
  static const minAppOpenViews = 5;
  static const rewardDuration = Duration(hours: 12);

  static bool canInterstitial({
    required bool viewerHome,
    required bool userStoppedVideo,
    required bool appForeground,
    required int completedViews,
    required Duration viewedFor,
    required int fullscreenToday,
    required DateTime now,
    DateTime? lastFullscreenAt,
  }) =>
      viewerHome &&
      userStoppedVideo &&
      appForeground &&
      completedViews >= minInterstitialViews &&
      viewedFor >= minViewDuration &&
      fullscreenToday < maxFullscreenPerDay &&
      (lastFullscreenAt == null ||
          now.difference(lastFullscreenAt) >= minBetweenFullscreen);

  static bool canAppOpen({
    required bool viewerHome,
    required bool warmReturn,
    required bool appForeground,
    required int completedViews,
    required Duration backgroundFor,
    required int fullscreenToday,
    required DateTime now,
    DateTime? lastFullscreenAt,
  }) =>
      viewerHome &&
      warmReturn &&
      appForeground &&
      completedViews >= minAppOpenViews &&
      backgroundFor >= minAppOpenBackground &&
      fullscreenToday < maxFullscreenPerDay &&
      (lastFullscreenAt == null ||
          now.difference(lastFullscreenAt) >= minBetweenAppOpens);

  static bool validCachedAppOpen(DateTime loadedAt, DateTime now) =>
      !now.isBefore(loadedAt) &&
      now.difference(loadedAt) < const Duration(hours: 4);
}

/// Local only: no Firebase billing or personal-data analytics.
class KyeobomAdLocalState {
  KyeobomAdLocalState._();
  static final instance = KyeobomAdLocalState._();
  static const _prefix = 'kyeobom_ad_frequency_v1_';
  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  Future<int> completeView() async {
    final count = (await _prefs.getInt('${_prefix}view_count') ?? 0) + 1;
    await _prefs.setInt('${_prefix}view_count', count);
    return count;
  }

  Future<int> completedViews() async =>
      await _prefs.getInt('${_prefix}view_count') ?? 0;

  Future<({int count, DateTime? last})> currentFullscreen(DateTime now) async {
    final day = '${now.year}-${now.month}-${now.day}';
    final savedDay = await _prefs.getString('${_prefix}day');
    final count = savedDay == day
        ? (await _prefs.getInt('${_prefix}daily_count') ?? 0)
        : 0;
    final time = await _prefs.getInt('${_prefix}last_fullscreen');
    return (
      count: count,
      last: time == null ? null : DateTime.fromMillisecondsSinceEpoch(time),
    );
  }

  Future<void> registerFullscreen(DateTime now) async {
    final current = await currentFullscreen(now);
    await _prefs.setString(
        '${_prefix}day', '${now.year}-${now.month}-${now.day}');
    await _prefs.setInt('${_prefix}daily_count', current.count + 1);
    await _prefs.setInt(
        '${_prefix}last_fullscreen', now.millisecondsSinceEpoch);
  }

  Future<DateTime?> rewardUntil() async {
    final millis = await _prefs.getInt('${_prefix}reward_until');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> hasAdFreeReward(DateTime now) async {
    final until = await rewardUntil();
    return until != null && until.isAfter(now);
  }

  Future<DateTime> grantReward(DateTime now) async {
    final until = now.add(KyeobomAdFrequency.rewardDuration);
    await _prefs.setInt('${_prefix}reward_until', until.millisecondsSinceEpoch);
    return until;
  }
}
