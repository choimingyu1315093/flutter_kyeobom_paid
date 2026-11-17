import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'kyeobom_ad_policy.dart';
import 'kyeobom_ad_metrics.dart';
import 'kyeobom_ad_frequency.dart';
import 'kyeobom_fullscreen_ads.dart';
import 'kyeobom_design.dart';

/// Production app enables ad requests explicitly at its root.
/// Standalone widget tests and previews can render the same dashboard without
/// invoking native UMP/AdMob method channels or holding background timers.
class KyeobomAdsRuntime extends InheritedWidget {
  const KyeobomAdsRuntime({super.key, required super.child});

  static bool enabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KyeobomAdsRuntime>() != null;

  @override
  bool updateShouldNotify(KyeobomAdsRuntime oldWidget) => false;
}

/// Shown ONLY below the controls on the portrait viewer dashboard.
/// It is not instantiated on the station or in the landscape/live view.
/// No interstitials, rewarded gates, app-open ads or full-screen overlays.
class KyeobomViewerHomeAd extends StatefulWidget {
  const KyeobomViewerHomeAd({super.key});

  @override
  State<KyeobomViewerHomeAd> createState() => _KyeobomViewerHomeAdState();
}

class _KyeobomViewerHomeAdState extends State<KyeobomViewerHomeAd> {
  static Future<void>? _sharedSdkInitialization;

  static Future<void> _initializeSdkOnce() =>
      _sharedSdkInitialization ??= _startSdk();

  static Future<void> _startSdk() async {
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
      );
      final status = await MobileAds.instance.initialize();
      if (kDebugMode) {
        for (final entry in status.adapterStatuses.entries) {
          debugPrint('[kyeobom/ads] mediation adapter ${entry.key}: '
              '${entry.value.state} · ${entry.value.description}');
        }
      }
    } catch (_) {
      // SDK failure can retry at the next dashboard entry.
      _sharedSdkInitialization = null;
      rethrow;
    }
  }

  BannerAd? _banner;
  NativeAd? _native;
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  bool _privacyRequired = false;
  bool _consentNeedsAction = false;
  bool _consentGranted = false;
  bool _rewardSuppressesHome = false;
  KyeobomAdFormat _format = KyeobomAdFormat.banner;
  int _adHeight = 0;
  bool _sdkInitialized = false;

  bool get _allowed => KyeobomAdsRuntime.enabled(context) &&
      KyeobomAdPolicy.isEnabled(
        platform: defaultTargetPlatform,
        release: kReleaseMode,
      );

  @override
  void initState() {
    super.initState();
    KyeobomFullscreenAds.instance.hideHomeAds.addListener(_onRewardChanged);
    // The ad SDK/UMP is never touched on station/streaming screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _allowed) unawaited(_prepare());
    });
  }

  void _onRewardChanged() {
    if (!mounted || _disposed) return;
    final rewarded = KyeobomFullscreenAds.instance.hideHomeAds.value;
    if (_rewardSuppressesHome == rewarded) return;
    if (rewarded) {
      final native = _native;
      final banner = _banner;
      setState(() {
        _rewardSuppressesHome = true;
        _loaded = false;
        _native = null;
        _banner = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (native != null) unawaited(native.dispose());
        if (banner != null) unawaited(banner.dispose());
      });
    } else {
      setState(() => _rewardSuppressesHome = false);
      if (_consentGranted) unawaited(_loadIfPermitted());
    }
  }

  Future<void> _refreshPrivacyRequirement() async {
    try {
      final requirement = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      if (mounted) {
        setState(() => _privacyRequired =
            requirement == PrivacyOptionsRequirementStatus.required);
      }
    } catch (_) {
      // Keep ad requests blocked unless UMP explicitly permits them.
    }
  }

  Future<void> _updateConsent() async {
    final completer = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!completer.isCompleted) completer.complete();
        },
        (FormError error) {
          if (kDebugMode) debugPrint('[kyeobom/ads] UMP: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(const Duration(seconds: 12));
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] UMP unavailable: $error');
    }
    if (mounted) await _refreshPrivacyRequirement();
  }

  Future<void> _prepare() async {
    if (_busy || _disposed || !_allowed) return;
    _busy = true;
    try {
      // Do not interrupt an urgent video check with an automatic consent form.
      // If required, show an opt-in entry point here and request NO ads.
      await _updateConsent();
      if (!mounted || _disposed) return;
      final permitted = await ConsentInformation.instance.canRequestAds();
      if (!mounted || _disposed) return;
      if (!permitted) {
        setState(() {
          _consentGranted = false;
          _consentNeedsAction = true;
        });
        return;
      }
      _consentGranted = true;
      await _loadIfPermitted();
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] $error');
    } finally {
      _busy = false;
    }
  }

  Future<void> _askForConsent() async {
    try {
      await _updateConsent();
      if (!mounted) return;
      final completed = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (kDebugMode && error != null) {
          debugPrint('[kyeobom/ads] UMP form: ${error.message}');
        }
        if (!completed.isCompleted) completed.complete();
      });
      await completed.future.timeout(const Duration(seconds: 50));
      if (!mounted) return;
      final permitted = await ConsentInformation.instance.canRequestAds();
      if (!mounted) return;
      setState(() {
        _consentGranted = permitted;
        _consentNeedsAction = !permitted;
      });
      if (permitted) {
        await _loadIfPermitted();
      } else {
        KyeobomFullscreenAds.instance.revokeConsent();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] consent form: $error');
    }
  }

  Future<void> _showPrivacyOptions() async {
    try {
      final done = Completer<void>();
      ConsentForm.showPrivacyOptionsForm((error) {
        if (kDebugMode && error != null) {
          debugPrint('[kyeobom/ads] privacy options: ${error.message}');
        }
        if (!done.isCompleted) done.complete();
      });
      await done.future.timeout(const Duration(seconds: 50));
      if (!mounted) return;
      final permitted = await ConsentInformation.instance.canRequestAds();
      _consentGranted = permitted;
      if (!permitted) {
        KyeobomFullscreenAds.instance.revokeConsent();
        final oldNative = _native;
        final oldBanner = _banner;
        setState(() {
          _loaded = false;
          _native = null;
          _banner = null;
          _consentNeedsAction = true;
        });
        // Unmount AdWidget before releasing the native platform view.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (oldNative != null) unawaited(oldNative.dispose());
          if (oldBanner != null) unawaited(oldBanner.dispose());
        });
      } else if (!_loaded) {
        setState(() => _consentNeedsAction = false);
        await _loadIfPermitted();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] privacy options: $error');
    }
  }

  Future<void> _loadIfPermitted() async {
    if (!mounted || _disposed || _loaded || !_allowed ||
        !_consentGranted) return;
    if (await KyeobomAdLocalState.instance.hasAdFreeReward(DateTime.now())) {
      KyeobomFullscreenAds.instance.hideHomeAds.value = true;
      return;
    }
    if (!_sdkInitialized) {
      await _initializeSdkOnce();
      _sdkInitialized = true;
    }
    if (!mounted || _disposed || _loaded) return;
    // Fullscreen mediation/ad loads must wait for Google SDK initialization.
    unawaited(KyeobomFullscreenAds.instance.onViewerHomeWithConsent());
    _format = await KyeobomAdPolicy.assignedFormat();
    if (!mounted || _disposed) return;
    final canNative = KyeobomAdPolicy.unitId(
      platform: defaultTargetPlatform,
      format: KyeobomAdFormat.native,
      release: kReleaseMode,
    ) != null;
    // iOS native template remains opt-in until its validator issue passes.
    // 360pt viewport leaves >=320pt after home horizontal padding.
    if (_format == KyeobomAdFormat.native && canNative &&
        KyeobomAdPolicy.nativeAllowed(defaultTargetPlatform) &&
        MediaQuery.sizeOf(context).width >= 360) {
      _loadNative();
    } else {
      await _loadBannerSafely();
    }
  }

  Future<void> _loadBannerSafely() async {
    try {
      await _loadBanner();
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] banner setup: $error');
    }
  }

  void _loadNative() {
    final id = KyeobomAdPolicy.unitId(
      platform: defaultTargetPlatform,
      format: KyeobomAdFormat.native,
      release: kReleaseMode,
    );
    if (id == null || _native != null || _banner != null ||
        !_consentGranted) return;
    _format = KyeobomAdFormat.native;
    final ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12,
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: KyeobomPalette.ink,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: KyeobomPalette.muted,
          size: 11,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: KyeobomPalette.navy,
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted || _disposed || !_consentGranted) {
            unawaited(ad.dispose());
            return;
          }
          KyeobomAdMetrics.record(KyeobomAdFormat.native, 'loaded');
          if (kDebugMode) {
            debugPrint('[kyeobom/ads] native mediation: '
                '${ad.responseInfo?.mediationAdapterClassName}');
          }
          setState(() {
            _loaded = true;
            // Room for the small native template and its attribution/CTA.
            _adHeight = 132;
          });
        },
        onAdFailedToLoad: (ad, error) {
          KyeobomAdMetrics.record(KyeobomAdFormat.native, 'failed');
          ad.dispose();
          if (!mounted || _disposed) return;
          _native = null;
          if (kDebugMode) debugPrint('[kyeobom/ads] native: $error');
          unawaited(_loadBannerSafely()); // Fallback, never duplicate ads.
        },
        onAdImpression: (_) =>
            KyeobomAdMetrics.record(KyeobomAdFormat.native, 'impression'),
        onAdClicked: (_) =>
            KyeobomAdMetrics.record(KyeobomAdFormat.native, 'clicked'),
        onPaidEvent: (_, micros, precision, currency) =>
            KyeobomAdMetrics.record(
              KyeobomAdFormat.native, 'paid',
              micros: micros, currency: currency,
            ),
      ),
    );
    _native = ad;
    KyeobomAdMetrics.record(KyeobomAdFormat.native, 'requested');
    unawaited(ad.load().catchError((Object error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] native load: $error');
      if (_native == ad) {
        _native = null;
        KyeobomAdMetrics.record(KyeobomAdFormat.native, 'failed');
        unawaited(ad.dispose());
        if (mounted && !_disposed) unawaited(_loadBannerSafely());
      }
    }));
  }

  Future<void> _loadBanner() async {
    final id = KyeobomAdPolicy.unitId(
      platform: defaultTargetPlatform,
      format: KyeobomAdFormat.banner,
      release: kReleaseMode,
    );
    if (id == null || _banner != null || _loaded || !mounted ||
        _disposed || !_consentGranted) return;
    _format = KyeobomAdFormat.banner;
    final available = (MediaQuery.sizeOf(context).width - 42).clamp(200, 460);
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
      available.toInt(),
    ) ?? AdSize.banner;
    if (!mounted || _disposed) return;
    final ad = BannerAd(
      adUnitId: id,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || _disposed || !_consentGranted) {
            unawaited(ad.dispose());
            return;
          }
          KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'loaded');
          if (kDebugMode) {
            debugPrint('[kyeobom/ads] banner mediation: '
                '${ad.responseInfo?.mediationAdapterClassName}');
          }
          setState(() {
            _loaded = true;
            _adHeight = size.height;
          });
        },
        onAdFailedToLoad: (ad, error) {
          KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'failed');
          ad.dispose();
          if (!mounted || _disposed) return;
          _banner = null;
          if (kDebugMode) debugPrint('[kyeobom/ads] banner: $error');
        },
        onAdImpression: (_) =>
            KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'impression'),
        onAdClicked: (_) =>
            KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'clicked'),
        onPaidEvent: (_, micros, precision, currency) =>
            KyeobomAdMetrics.record(
              KyeobomAdFormat.banner, 'paid',
              micros: micros, currency: currency,
            ),
      ),
    );
    _banner = ad;
    KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'requested');
    unawaited(ad.load().catchError((Object error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] banner load: $error');
      if (_banner == ad) {
        _banner = null;
        KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'failed');
        unawaited(ad.dispose());
      }
    }));
  }

  void _clearAd() {
    _loaded = false;
    final oldNative = _native;
    final oldBanner = _banner;
    _native = null;
    _banner = null;
    // Google recommends disposing a native platform ad AFTER AdWidget is
    // unmounted. Releasing it during a live-view route/orientation change can
    // leave a native UIKit overlay above Flutter's camera controls on iOS.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (oldNative != null) unawaited(oldNative.dispose());
      if (oldBanner != null) unawaited(oldBanner.dispose());
    });
  }

  Future<void> _showMetrics() async {
    final data = await KyeobomAdMetrics.localReport();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('광고 QA (로컬 데이터)'),
        content: SelectableText(data),
        actions: [
          if (kDebugMode)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                MobileAds.instance.openAdInspector((error) {
                  if (error != null) {
                    debugPrint('[kyeobom/ads] inspector: $error');
                  }
                });
              },
              child: const Text('광고 인스펙터'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    KyeobomFullscreenAds.instance.hideHomeAds.removeListener(_onRewardChanged);
    _clearAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    // A failed/no-fill ad occupies no ad space so the viewer's main action
    // always remains obvious and unobstructed.
    if (!_loaded && !_rewardSuppressesHome &&
        !_consentNeedsAction && !_privacyRequired && !kDebugMode &&
        !KyeobomAdPolicy.enableRewarded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        // This widget is mounted as Scaffold.bottomNavigationBar on taller
        // phones. MainAxisSize.max used to consume the whole viewport,
        // hiding the home body and its "실시간 보기" button behind the ad.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rewardSuppressesHome)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Text(
                '선택한 보상으로 홈 광고가 12시간 숨겨졌어요.',
                style: TextStyle(color: KyeobomPalette.muted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          if (_loaded) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 7),
              child: Text('광고', style: TextStyle(
                color: KyeobomPalette.muted, fontSize: 11,
              )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: KyeobomPalette.border),
                borderRadius: BorderRadius.circular(12),
              ),
              // Explicit vertical bounds prevent the platform ad layout
              // from expanding the bottom navigation to screen height.
              child: SizedBox(
                height: _adHeight.toDouble(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final native = _native;
                    final banner = _banner;
                    final available = constraints.maxWidth.isFinite
                        ? constraints.maxWidth : 400.0;
                    final width = native != null
                        ? available.clamp(0.0, 400.0).toDouble()
                        : banner!.size.width.toDouble();
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: _adHeight.toDouble(),
                        child: AdWidget(ad: native ?? banner!),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (_consentNeedsAction)
            TextButton.icon(
              onPressed: _askForConsent,
              icon: const Icon(Icons.privacy_tip_outlined, size: 16),
              label: const Text('광고 및 개인정보 선택',
                style: TextStyle(fontSize: 12)),
            ),
          if (_privacyRequired)
            TextButton(
              onPressed: _showPrivacyOptions,
              child: const Text('광고 개인정보 설정',
                style: TextStyle(fontSize: 11)),
            ),
          if (KyeobomAdPolicy.enableRewarded && !_rewardSuppressesHome)
            ValueListenableBuilder<bool>(
              valueListenable: KyeobomFullscreenAds.instance.rewardedAvailable,
              builder: (context, available, child) => available
                  ? TextButton.icon(
                      onPressed: () => unawaited(
                        KyeobomFullscreenAds.instance.showRewardedOnTap()),
                      icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                      label: const Text('선택 광고 시청 후 홈 광고 12시간 숨기기',
                        style: TextStyle(fontSize: 11)),
                    )
                  : const SizedBox.shrink(),
            ),
          if (kDebugMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showMetrics,
                child: Text('광고 QA · ${_format.name}',
                  style: const TextStyle(fontSize: 10)),
              ),
            ),
        ],
      ),
    );
  }
}
