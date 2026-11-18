import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'homecam_emulator_qa.dart';

/// Resets iOS Keychain-backed Firebase Auth when app-install preferences are
/// new, and prevents a local QA emulator identity from crossing into the
/// production Firebase backend. Android uses the same safe behavior.
///
/// Firebase Auth can survive iOS uninstall/reinstall while NSUserDefaults
/// (used by shared_preferences) does not. This runs BEFORE choosing the first
/// route, restoring viewer grants or starting the camera station.
abstract final class HomeCamAuthRealmGuard {
  static const installRealmKey = 'kyeobom_auth_install_realm_v1';

  static String realmFor({
    required String projectId,
    required bool emulator,
    String emulatorHost = '',
  }) =>
      emulator
          ? 'emulator:$projectId:$emulatorHost'
          : 'production:$projectId';

  /// Testable, fail-closed transition. The marker MUST be committed only after
  /// any old Firebase Auth identity is signed out. Never delete cloud users or
  /// Firestore documents here.
  static Future<bool> ensureRealm({
    required String expectedRealm,
    required Future<String?> Function() readRealm,
    required Future<void> Function() discardCachedAuth,
    required Future<void> Function(String realm) writeRealm,
  }) async {
    if (await readRealm() == expectedRealm) return false;

    // A missing marker means new install (not necessarily a new Keychain);
    // a changed marker means QA <-> production was switched.
    await discardCachedAuth();
    await writeRealm(expectedRealm);
    return true;
  }

  static Future<void> prepare() async {
    final auth = FirebaseAuth.instance;
    final prefs = SharedPreferencesAsync();
    final realm = realmFor(
      projectId: auth.app.options.projectId,
      emulator: HomeCamEmulatorQa.enabled,
      emulatorHost: HomeCamEmulatorQa.host,
    );

    final cleared = await ensureRealm(
      expectedRealm: realm,
      readRealm: () => prefs.getString(installRealmKey),
      // Always call native signOut, even when currentUser appears null:
      // iOS may still be restoring a Keychain-backed session.
      discardCachedAuth: () => auth.signOut(),
      writeRealm: (value) => prefs.setString(installRealmKey, value),
    );
    if (cleared) {
      debugPrint('[kyeobom/auth] First install or Firebase backend changed; '
          'cleared locally cached session before first route');
    }
  }
}
