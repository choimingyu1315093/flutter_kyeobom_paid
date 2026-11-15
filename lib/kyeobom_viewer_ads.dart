import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kyeobom_ad_policy.dart';
import 'kyeobom_design.dart';

/// Local-only QA/A-B counters. No Firebase writes and NO camera data.
/// AdMob's own dashboard remains authoritative for actual settlement.
abstract final class KyeobomAdMetrics {
  static Future<void> _pending = Future<void>.value();

  static void record(KyeobomAdFormat format, String event,
      {double micros = 0, String currency = ''}) {
    _pending = _pending.then((_) async {
      try {
        final prefs = SharedPreferencesAsync();
        final type = format.name;
        final key = 'kyeobom_ads_v1_${type}_${event}';
        await prefs.setInt(key, (await prefs.getInt(key) ?? 0) + 1);
        if (event == 'paid' && micros > 0 && currency.isNotEmpty) {
          final currencyKey = 'kyeobom_ads_v1_${type}_paid_${currency}';
          await prefs.setInt(currencyKey,
              (await prefs.getInt(currencyKey) ?? 0) + micros.round());
        }
      } catch (_) {
        // Never introduce server calls or affect video for ad metrics.
      }
    }).catchError((Object _) {});
  }

  static Future<String> localReport() async {
    await _pending.catchError((Object _) {});
    final prefs = SharedPreferencesAsync();
    final rows = <String>[];
    for (final type in KyeobomAdFormat.values) {
      final values = <String>[];
      for (final event in ['loaded', 'impression', 'clicked', 'paid', 'failed']) {
        final count = await prefs.getInt('kyeobom_ads_v1_${type.name}_$event') ?? 0;
        values.add('$event=$count');
      }
      rows.add('${type.name}: ${values.join(', ')}');
    }
    return rows.join('\n');
  }
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
      await MobileAds.instance.initialize();
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
  KyeobomAdFormat _format = KyeobomAdFormat.banner;
  int _adHeight = 0;
  bool _sdkInitialized = false;

  bool get _allowed => KyeobomAdPolicy.isEnabled(
        platform: defaultTargetPlatform,
        release: kReleaseMode,
      );

  @override
  void initState() {
    super.initState();
    // The ad SDK/UMP is never touched on station/streaming screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _allowed) unawaited(_prepare());
    });
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
        setState(() => _consentNeedsAction = true);
        return;
      }
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
      setState(() => _consentNeedsAction = !permitted);
      if (permitted) await _loadIfPermitted();
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
      if (!permitted) {
        _clearAd();
        setState(() => _consentNeedsAction = true);
      } else if (!_loaded) {
        await _loadIfPermitted();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[kyeobom/ads] privacy options: $error');
    }
  }

  Future<void> _loadIfPermitted() async {
    if (!mounted || _disposed || _loaded || !_allowed) return;
    if (!_sdkInitialized) {
      await _initializeSdkOnce();
      _sdkInitialized = true;
    }
    if (!mounted || _disposed || _loaded) return;
    _format = await KyeobomAdPolicy.assignedFormat();
    if (!mounted || _disposed) return;
    final canNative = KyeobomAdPolicy.unitId(
      platform: defaultTargetPlatform,
      format: KyeobomAdFormat.native,
      release: kReleaseMode,
    ) != null;
    if (_format == KyeobomAdFormat.native && canNative &&
        MediaQuery.sizeOf(context).width >= 345) {
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
    if (id == null || _native != null || _banner != null) return;
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
          if (!mounted || _disposed) {
            ad.dispose();
            return;
          }
          KyeobomAdMetrics.record(KyeobomAdFormat.native, 'loaded');
          setState(() {
            _loaded = true;
            _adHeight = 110;
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
    if (id == null || _banner != null || _loaded || !mounted || _disposed) return;
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
          if (!mounted || _disposed) {
            ad.dispose();
            return;
          }
          KyeobomAdMetrics.record(KyeobomAdFormat.banner, 'loaded');
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
    _native?.dispose();
    _native = null;
    _banner?.dispose();
    _banner = null;
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
    _clearAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    // A failed/no-fill ad occupies no ad space so the viewer's main action
    // always remains obvious and unobstructed.
    if (!_loaded && !_consentNeedsAction && !_privacyRequired && !kDebugMode) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              child: SizedBox(
                width: double.infinity,
                height: _adHeight.toDouble(),
                child: _native != null
                    ? AdWidget(ad: _native!)
                    : AdWidget(ad: _banner!),
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
