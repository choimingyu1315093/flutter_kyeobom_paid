import 'package:shared_preferences/shared_preferences.dart';

import 'kyeobom_ad_policy.dart';

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

