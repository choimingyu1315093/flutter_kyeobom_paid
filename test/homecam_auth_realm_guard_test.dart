import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_auth_realm_guard.dart';

void main() {
  test('fresh iOS installation clears restored Keychain auth before marker',
      () async {
    final events = <String>[];
    String? marker;
    final cleared = await HomeCamAuthRealmGuard.ensureRealm(
      expectedRealm: 'production:homecamera-13091',
      readRealm: () async {
        events.add('read');
        return marker;
      },
      discardCachedAuth: () async {
        events.add('signout');
      },
      writeRealm: (realm) async {
        events.add('write');
        marker = realm;
      },
    );
    expect(cleared, isTrue);
    expect(events, ['read', 'signout', 'write']);
    expect(marker, 'production:homecamera-13091');
  });

  test('ordinary app restart keeps current valid authenticated session',
      () async {
    var signOutCalls = 0;
    var writeCalls = 0;
    final cleared = await HomeCamAuthRealmGuard.ensureRealm(
      expectedRealm: 'production:homecamera-13091',
      readRealm: () async => 'production:homecamera-13091',
      discardCachedAuth: () async { signOutCalls++; },
      writeRealm: (_) async { writeCalls++; },
    );
    expect(cleared, isFalse);
    expect(signOutCalls, 0);
    expect(writeCalls, 0);
  });

  test('moving from local Firebase emulator to production drops QA user',
      () async {
    final events = <String>[];
    final cleared = await HomeCamAuthRealmGuard.ensureRealm(
      expectedRealm: 'production:homecamera-13091',
      readRealm: () async => 'emulator:homecamera-13091:192.168.0.19',
      discardCachedAuth: () async { events.add('signout'); },
      writeRealm: (_) async { events.add('store'); },
    );
    expect(cleared, isTrue);
    expect(events, ['signout', 'store']);
  });

  test('moving from production into emulator also drops production user',
      () async {
    final events = <String>[];
    await HomeCamAuthRealmGuard.ensureRealm(
      expectedRealm: 'emulator:homecamera-13091:192.168.0.19',
      readRealm: () async => 'production:homecamera-13091',
      discardCachedAuth: () async { events.add('signout'); },
      writeRealm: (_) async { events.add('store'); },
    );
    expect(events, ['signout', 'store']);
  });

  test('changing emulator Mac IP resets the emulator test Auth user',
      () async {
    var resets = 0;
    await HomeCamAuthRealmGuard.ensureRealm(
      expectedRealm: 'emulator:homecamera-13091:192.168.0.20',
      readRealm: () async => 'emulator:homecamera-13091:192.168.0.19',
      discardCachedAuth: () async { resets++; },
      writeRealm: (_) async {},
    );
    expect(resets, 1);
  });

  test('signOut failure does not mark installation initialized', () async {
    var markerWrites = 0;
    await expectLater(
      HomeCamAuthRealmGuard.ensureRealm(
        expectedRealm: 'production:homecamera-13091',
        readRealm: () async => null,
        discardCachedAuth: () async => throw StateError('signout failed'),
        writeRealm: (_) async { markerWrites++; },
      ),
      throwsStateError,
    );
    expect(markerWrites, 0);
  });

  test('production and emulator realms never share the startup marker', () {
    final production = HomeCamAuthRealmGuard.realmFor(
      projectId: 'homecamera-13091', emulator: false,
    );
    final emulator = HomeCamAuthRealmGuard.realmFor(
      projectId: 'homecamera-13091',
      emulator: true, emulatorHost: '192.168.0.19',
    );
    expect(production, 'production:homecamera-13091');
    expect(emulator, 'emulator:homecamera-13091:192.168.0.19');
    expect(production, isNot(emulator));
  });

  test('bootstrap is awaited after emulator routing and before first screen',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final init = source.indexOf('await RemoteControl.instance.initialize()');
    final qa = source.indexOf('await HomeCamEmulatorQa.configure()');
    final guard = source.indexOf('await HomeCamAuthRealmGuard.prepare()');
    final restore =
        source.indexOf('await RemoteControl.instance.restoreViewerPairing()');
    final app = source.indexOf('runApp(const HomeCameraApp())');
    expect(init, greaterThanOrEqualTo(0));
    expect(qa, greaterThan(init));
    expect(guard, greaterThan(qa));
    expect(restore, greaterThan(guard));
    expect(app, greaterThan(restore));
  });
}
