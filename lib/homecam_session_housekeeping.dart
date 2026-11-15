import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_control.dart';

/// Opportunistic, client-side removal of expired, *ended* signaling sessions.
///
/// No Cloud Functions, scheduled server jobs or Firestore TTL (which requires
/// billing). Runs only when a signed-in app starts, at most once per day on
/// each device; never scans or deletes a live session.
abstract final class HomeCamSessionHousekeeping {
  static const _runEvery = Duration(hours: 24);
  static const _keepEndedFor = Duration(hours: 48);
  static const _maxSessionsPerRun = 12;

  /// Only sessions explicitly ended for more than 48 hours qualify.
  /// An active session is never removed, regardless of its duration.
  static bool shouldRemove(Map<String, dynamic> data, DateTime now) {
    final endedAt = data['endedAt'];
    return data['state'] == 'ended' &&
        endedAt is Timestamp &&
        endedAt.toDate().isBefore(now.subtract(_keepEndedFor));
  }

  static Future<void> runIfDue() async {
    final account = FirebaseAuth.instance.currentUser;
    if (account == null) return;
    final prefs = SharedPreferencesAsync();
    final key = 'homecam_session_cleanup_v1_${account.uid}';
    try {
      final now = DateTime.now();
      final previous = await prefs.getInt(key);
      if (previous != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(previous);
        final elapsed = now.difference(last);
        if (!elapsed.isNegative && elapsed < _runEvery) return;
      }

      // A query ordered by endedAt only returns sessions actually closed by
      // one side. Never delete sessions that might still be transmitting.
      final results = await RemoteControl.instance.station
          .collection('sessions')
          .orderBy('endedAt')
          .limit(_maxSessionsPerRun)
          .get();

      for (final session in results.docs) {
        if (!shouldRemove(session.data(), now)) continue;

        // Firestore does NOT recursively delete nested collections.
        // Keep these known signaling subcollections tidy as well.
        for (final name in ['stationCandidates', 'viewerCandidates']) {
          await _deleteCandidates(session.reference.collection(name));
        }
        await session.reference.delete();
      }
      await prefs.setInt(key, now.millisecondsSinceEpoch);
    } catch (_) {
      // Network failures or quota limits must not block login or camera use.
      // No timestamp is saved on failure, so a future app launch can retry.
    }
  }

  static Future<void> _deleteCandidates(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final page = await collection.limit(150).get();
      if (page.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final document in page.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
      if (page.docs.length < 150) break;
    }
  }
}
