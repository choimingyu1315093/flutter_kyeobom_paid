import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'kyeobom_ad_frequency.dart';
import 'kyeobom_ad_metrics.dart';
import 'kyeobom_ad_policy.dart';

/// ONE shared controller for the viewer role; never used by the station.
/// The Google SDK can be initialized after the home widget's UMP gate.
///
/// App-open and interstitial require separately enabled --dart-define gates.
/// Fullscreen ads are NEVER requested or shown during a live viewing session.
class KyeobomFullscreenAds {
  KyeobomFullscreenAds._();
  static final instance = KyeobomFullscreenAds._();

  final ValueNotifier<bool> rewardedAvailable = ValueNotifier(false);
  final ValueNotifier<bool> hideHomeAds = ValueNotifier(false);

  AppOpenAd? _appOpen;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  DateTime? _appOpenLoadedAt;
  DateTime? _interstitialLoadedAt;
  DateTime? _backgroundedAt;

  bool _viewerHome = false;
  bool _live = false;
  bool _foreground = true;
  bool _consentAllowed = false;
  bool _showing = false;
  bool _loadAppOpenInProgress = false;
  bool _loadInterstitialInProgress = false;
  bool _loadRewardedInProgress = false;
  bool _ignoreNextForeground = false;

  bool get isShowing => _showing;

  bool _enabled(KyeobomAdFormat format) {
    final supported = KyeobomAdPolicy.isEnabled(
      platform: defaultTargetPlatform, release: kReleaseMode,
    );
    return supported &&
        KyeobomAdPolicy.formatEnabled(format) &&
        KyeobomAdPolicy.unitId(
          platform: defaultTargetPlatform,
          format: format,
          release: kReleaseMode,
        ) != null;
  }

  String? _id(KyeobomAdFormat format) => KyeobomAdPolicy.unitId(
        platform: defaultTargetPlatform,
        format: format,
        release: kReleaseMode,
      );

  /// Called only after an on-screen viewer UMP consent check, never by camera.
  Future<void> onViewerHomeWithConsent() async {
    _viewerHome = true;
    _live = false;
    _foreground = true;
    _consentAllowed = await ConsentInformation.instance.canRequestAds();
    if (!_consentAllowed) {
      revokeConsent();
      return;
    }
    hideHomeAds.value =
        await KyeobomAdLocalState.instance.hasAdFreeReward(DateTime.now());
    final viewed = await KyeobomAdLocalState.instance.completedViews();
    if (!_viewerHome || _live || !_consentAllowed) return;

    if (_enabled(KyeobomAdFormat.interstitial) &&
        viewed >= KyeobomAdFrequency.minInterstitialViews - 1) {
      _loadInterstitial();
    }
    if (_enabled(KyeobomAdFormat.appOpen) &&
        viewed >= KyeobomAdFrequency.minAppOpenViews - 1) {
      _loadAppOpen();
    }
    if (_enabled(KyeobomAdFormat.rewarded) && !hideHomeAds.value) {
      _loadRewarded();
    }
  }

  void beginLive() {
    _live = true;
    _viewerHome = false;
    _backgroundedAt = null;
  }

  void leaveViewer() {
    _viewerHome = false;
    _live = false;
    _backgroundedAt = null;
  }

  void appBackgrounded() {
    _foreground = false;
    _backgroundedAt = DateTime.now();
  }

  /// Warm foreground only. No cold-start, station or live-view monetization.
  Future<void> appForegrounded() async {
    final previous = _backgroundedAt;
    _backgroundedAt = null;
    _foreground = true;
    if (_ignoreNextForeground) {
      _ignoreNextForeground = false;
      return;
    }
    if (previous == null || !_viewerHome || _live || _showing ||
        !_consentAllowed || !_enabled(KyeobomAdFormat.appOpen)) return;
    final now = DateTime.now();
    final ad = _appOpen;
    final loaded = _appOpenLoadedAt;
    if (ad == null || loaded == null ||
        !KyeobomAdFrequency.validCachedAppOpen(loaded, now)) {
      _discardExpiredAppOpen();
      _loadAppOpen();
      return;
    }
    final usage = await KyeobomAdLocalState.instance.currentFullscreen(now);
    final views = await KyeobomAdLocalState.instance.completedViews();
    if (_viewerHome && !_live && _foreground &&
        KyeobomAdFrequency.canAppOpen(
          viewerHome: _viewerHome,
          warmReturn: true,
          appForeground: _foreground,
          completedViews: views,
          backgroundFor: now.difference(previous),
          fullscreenToday: usage.count,
          now: now,
          lastFullscreenAt: usage.last,
        )) {
      _showAppOpen();
    }
  }

  /// Only an explicit in-app "End viewing" -> dashboard transition qualifies.
  /// App background, app exit, back navigation and video errors do NOT.
  Future<void> completedLiveView({
    required Duration viewedFor,
    required bool explicitStop,
  }) async {
    _live = false;
    _viewerHome = true;
    final views = await KyeobomAdLocalState.instance.completeView();
    if (!_enabled(KyeobomAdFormat.interstitial) ||
        !_foreground || !_consentAllowed || !explicitStop || _showing) {
      return;
    }
    final now = DateTime.now();
    final history = await KyeobomAdLocalState.instance.currentFullscreen(now);
    if (!_viewerHome || _live ||
        !KyeobomAdFrequency.canInterstitial(
          viewerHome: true,
          userStoppedVideo: explicitStop,
          appForeground: _foreground,
          completedViews: views,
          viewedFor: viewedFor,
          fullscreenToday: history.count,
          now: now,
          lastFullscreenAt: history.last,
        )) {
      if (views >= KyeobomAdFrequency.minInterstitialViews - 1) {
        _loadInterstitial();
      }
      return;
    }
    if (_interstitial != null &&
        _interstitialLoadedAt != null &&
        now.difference(_interstitialLoadedAt!) < const Duration(hours: 1)) {
      _showInterstitial();
    } else {
      _discardInterstitial();
      _loadInterstitial(); // Never wait for an ad at a navigation boundary.
    }
  }

  void _loadInterstitial() {
    if (!_viewerHome || _live || !_foreground || !_consentAllowed ||
        !_enabled(KyeobomAdFormat.interstitial) ||
        _interstitial != null || _loadInterstitialInProgress) return;
    final unit = _id(KyeobomAdFormat.interstitial);
    if (unit == null) return;
    _loadInterstitialInProgress = true;
    unawaited(InterstitialAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadInterstitialInProgress = false;
          if (!_consentAllowed) {
            unawaited(ad.dispose());
            return;
          }
          _interstitial = ad;
          _interstitialLoadedAt = DateTime.now();
          KyeobomAdMetrics.record(KyeobomAdFormat.interstitial, 'loaded');
        },
        onAdFailedToLoad: (error) {
          _loadInterstitialInProgress = false;
          KyeobomAdMetrics.record(KyeobomAdFormat.interstitial, 'failed');
          if (kDebugMode) debugPrint('[kyeobom/ads] interstitial: $error');
        },
      ),
    ).catchError((Object error) {
      _loadInterstitialInProgress = false;
      if (kDebugMode) debugPrint('[kyeobom/ads] interstitial load: $error');
    }));
  }

  void _showInterstitial() {
    final ad = _interstitial;
    if (ad == null || _showing || _live || !_viewerHome || !_foreground) return;
    _interstitial = null;
    _interstitialLoadedAt = null;
    _showing = true;
    _ignoreNextForeground = true;
    ad.onPaidEvent = (_, micros, precision, currency) =>
        KyeobomAdMetrics.record(KyeobomAdFormat.interstitial, 'paid',
            micros: micros, currency: currency);
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        KyeobomAdMetrics.record(KyeobomAdFormat.interstitial, 'impression');
        unawaited(KyeobomAdLocalState.instance.registerFullscreen(DateTime.now()));
      },
      onAdClicked: (_) =>
          KyeobomAdMetrics.record(KyeobomAdFormat.interstitial, 'clicked'),
      onAdDismissedFullScreenContent: (_) {
        _showing = false;
        unawaited(ad.dispose());
        if (_viewerHome && !_live) _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        _showing = false;
        unawaited(ad.dispose());
        if (kDebugMode) debugPrint('[kyeobom/ads] interstitial show: $error');
      },
    );
    unawaited(ad.show().catchError((Object error) {
      _showing = false;
      unawaited(ad.dispose());
      if (kDebugMode) debugPrint('[kyeobom/ads] interstitial show: $error');
    }));
  }

  void _loadAppOpen() {
    if (!_viewerHome || _live || !_foreground || !_consentAllowed ||
        !_enabled(KyeobomAdFormat.appOpen) ||
        _appOpen != null || _loadAppOpenInProgress) return;
    final unit = _id(KyeobomAdFormat.appOpen);
    if (unit == null) return;
    _loadAppOpenInProgress = true;
    unawaited(AppOpenAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadAppOpenInProgress = false;
          if (!_consentAllowed) {
            unawaited(ad.dispose());
            return;
          }
          _appOpen = ad;
          _appOpenLoadedAt = DateTime.now();
          KyeobomAdMetrics.record(KyeobomAdFormat.appOpen, 'loaded');
        },
        onAdFailedToLoad: (error) {
          _loadAppOpenInProgress = false;
          KyeobomAdMetrics.record(KyeobomAdFormat.appOpen, 'failed');
          if (kDebugMode) debugPrint('[kyeobom/ads] app open: $error');
        },
      ),
    ).catchError((Object error) {
      _loadAppOpenInProgress = false;
      if (kDebugMode) debugPrint('[kyeobom/ads] app open load: $error');
    }));
  }

  void _discardExpiredAppOpen() {
    final ad = _appOpen;
    _appOpen = null;
    _appOpenLoadedAt = null;
    if (ad != null) unawaited(ad.dispose());
  }

  void _discardInterstitial() {
    final ad = _interstitial;
    _interstitial = null;
    _interstitialLoadedAt = null;
    if (ad != null) unawaited(ad.dispose());
  }

  void _showAppOpen() {
    final ad = _appOpen;
    if (ad == null || _showing || !_viewerHome || _live || !_foreground) return;
    _appOpen = null;
    _appOpenLoadedAt = null;
    _showing = true;
    _ignoreNextForeground = true;
    ad.onPaidEvent = (_, micros, precision, currency) =>
        KyeobomAdMetrics.record(KyeobomAdFormat.appOpen, 'paid',
            micros: micros, currency: currency);
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (_) {
        KyeobomAdMetrics.record(KyeobomAdFormat.appOpen, 'impression');
        unawaited(KyeobomAdLocalState.instance.registerFullscreen(DateTime.now()));
      },
      onAdClicked: (_) =>
          KyeobomAdMetrics.record(KyeobomAdFormat.appOpen, 'clicked'),
      onAdDismissedFullScreenContent: (_) {
        _showing = false;
        unawaited(ad.dispose());
        if (_viewerHome && !_live) _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        _showing = false;
        unawaited(ad.dispose());
        if (kDebugMode) debugPrint('[kyeobom/ads] app open show: $error');
      },
    );
    unawaited(ad.show().catchError((Object error) {
      _showing = false;
      unawaited(ad.dispose());
      if (kDebugMode) debugPrint('[kyeobom/ads] app open show: $error');
    }));
  }

  void _loadRewarded() {
    if (!_viewerHome || _live || !_foreground || !_consentAllowed ||
        !_enabled(KyeobomAdFormat.rewarded) ||
        hideHomeAds.value || _rewarded != null || _loadRewardedInProgress) {
      return;
    }
    final unit = _id(KyeobomAdFormat.rewarded);
    if (unit == null) return;
    _loadRewardedInProgress = true;
    unawaited(RewardedAd.load(
      adUnitId: unit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadRewardedInProgress = false;
          if (!_consentAllowed) {
            unawaited(ad.dispose());
            return;
          }
          _rewarded = ad;
          rewardedAvailable.value = true;
          KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'loaded');
        },
        onAdFailedToLoad: (error) {
          _loadRewardedInProgress = false;
          rewardedAvailable.value = false;
          KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'failed');
          if (kDebugMode) debugPrint('[kyeobom/ads] rewarded: $error');
        },
      ),
    ).catchError((Object error) {
      _loadRewardedInProgress = false;
      rewardedAvailable.value = false;
      if (kDebugMode) debugPrint('[kyeobom/ads] rewarded load: $error');
    }));
  }

  /// Only the direct user opt-in button invokes this method.
  /// Reward is home-ad suppression for 12 hours, NEVER access to camera.
  Future<void> showRewardedOnTap() async {
    if (!_viewerHome || _live || !_foreground || _showing ||
        !_consentAllowed || !_enabled(KyeobomAdFormat.rewarded)) return;
    final ad = _rewarded;
    if (ad == null) return;
    final canRequest = await ConsentInformation.instance.canRequestAds();
    if (!canRequest || !_viewerHome || _live || _showing) return;
    _rewarded = null;
    rewardedAvailable.value = false;
    _showing = true;
    _ignoreNextForeground = true;
    ad.onPaidEvent = (_, micros, precision, currency) =>
        KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'paid',
            micros: micros, currency: currency);
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdShowedFullScreenContent: (_) =>
          KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'impression'),
      onAdClicked: (_) =>
          KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'clicked'),
      onAdDismissedFullScreenContent: (_) {
        _showing = false;
        unawaited(ad.dispose());
        if (_viewerHome && !_live && !hideHomeAds.value) _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        _showing = false;
        unawaited(ad.dispose());
        if (kDebugMode) debugPrint('[kyeobom/ads] reward show: $error');
      },
    );
    unawaited(ad.show(
      onUserEarnedReward: (ad, reward) {
        unawaited(_grantHomeAdFreeReward());
      },
    ).catchError((Object error) {
      _showing = false;
      unawaited(ad.dispose());
      if (kDebugMode) debugPrint('[kyeobom/ads] reward show: $error');
    }));
  }

  Future<void> _grantHomeAdFreeReward() async {
    await KyeobomAdLocalState.instance.grantReward(DateTime.now());
    KyeobomAdMetrics.record(KyeobomAdFormat.rewarded, 'earned');
    hideHomeAds.value = true;
    final ad = _rewarded;
    _rewarded = null;
    rewardedAvailable.value = false;
    if (ad != null) unawaited(ad.dispose());
  }

  void revokeConsent() {
    _consentAllowed = false;
    rewardedAvailable.value = false;
    _discardExpiredAppOpen();
    _discardInterstitial();
    final ad = _rewarded;
    _rewarded = null;
    if (ad != null) unawaited(ad.dispose());
  }
}
