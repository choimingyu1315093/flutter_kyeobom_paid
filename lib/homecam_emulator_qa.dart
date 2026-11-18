import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Opt-in, DEBUG-ONLY transport switch for two physical phones on the same
/// trusted Wi-Fi as the Mac Firebase Emulator Suite.
///
/// QA never uses a production Firestore or Auth endpoint after this hook runs.
/// Do not enable on a release build. Other Firebase services are not routed.
abstract final class HomeCamEmulatorQa {
  static bool get enabled =>
      kDebugMode &&
      const bool.fromEnvironment('KYEOBOM_USE_FIREBASE_EMULATORS');

  static const host = String.fromEnvironment('KYEOBOM_EMULATOR_HOST');

  static Future<void> configure() async {
    if (!enabled) return;
    if (host.trim().isEmpty || host == 'localhost' ||
        host == '127.0.0.1' || host == '0.0.0.0') {
      throw StateError(
        '실기기 QA용 Mac 내부망 IP가 없습니다. '
        '--dart-define=KYEOBOM_EMULATOR_HOST=Mac_LAN_IP를 설정해 주세요.',
      );
    }
    // First check raw connectivity. A missing LAN port/firewall permission
    // must not become an opaque Firebase 'internal-error' during registration.
    for (final port in [9099, 8080]) {
      try {
        final socket = await Socket.connect(
          host, port, timeout: const Duration(seconds: 3),
        );
        socket.destroy();
      } catch (error) {
        throw StateError('Mac Firebase 테스트 서버 $host:$port 접속 실패. '
            '서버 실행 상태, 같은 Wi-Fi, 방화벽과 iOS 로컬 네트워크 허용을 '
            '확인하세요. 원인: $error');
      }
    }
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    debugPrint('[kyeobom/qa] Auth 9099 + Firestore 8080 -> $host');
    debugPrint('[kyeobom/qa] projectId = '
        '${FirebaseAuth.instance.app.options.projectId}');
    debugPrint('[kyeobom/qa] LOCAL EMULATORS ONLY; never publish this build');
  }
}
