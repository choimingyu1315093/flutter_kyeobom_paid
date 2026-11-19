import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_control.dart';
import 'webrtc_session.dart';
import 'audio_session.dart';
import 'video_orientation.dart';
import 'viewer_video_controls.dart';
import 'kyeobom_design.dart';
import 'kyeobom_screens.dart';
import 'kyeobom_viewer_ads.dart';
import 'kyeobom_fullscreen_ads.dart';
import 'kyeobom_auth_screens.dart';
import 'kyeobom_station_start_dialog.dart';
import 'homecam_session_housekeeping.dart';
import 'homecam_pairing_screens.dart';
import 'homecam_recovery_policy.dart';
import 'homecam_emulator_qa.dart';
import 'homecam_auth_realm_guard.dart';
import 'device_health.dart';
import 'device_health_policy.dart';
import 'health_push_messaging.dart';
import 'event_recording_controller.dart';
import 'event_clips_screen.dart';
import 'baby_sound_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RemoteControl.instance.initialize();
    // Optional local-only testing: never touch production Auth or Firestore
    // while the special debug flag is enabled.
    await HomeCamEmulatorQa.configure();
    // iOS can retain Firebase Auth in Keychain after app deletion. A fresh
    // install, or switching local QA <-> production, must never silently
    // restore the old camera-station identity before showing the first route.
    // Do not continue to StationScreen if clearing the local identity fails.
    try {
      await HomeCamAuthRealmGuard.prepare();
    } catch (error) {
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '기존 로그인 정보를 초기화하지 못했어요. '
                '앱을 완전히 종료한 뒤 다시 실행해 주세요.'
                '\n\n오류: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ));
      return;
    }
    await RemoteControl.instance.restoreViewerPairing();
    // Non-blocking: at most one small free-tier cleanup per device/day.
    // Never touch ongoing WebRTC sessions or delay showing the UI.
    unawaited(HomeCamSessionHousekeeping.runIfDue());
  } catch (error) {
    if (HomeCamEmulatorQa.enabled) {
      // Fail CLOSED. A misconfigured QA emulator must never silently send
      // test registration or camera signaling to a real Firebase project.
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Firebase 에뮬레이터 QA 초기화 실패: $error'),
          )),
        ),
      ));
      return;
    }
    // A clear setup prompt is shown below when Firebase is unavailable.
  }
  runApp(const HomeCameraApp());
}

class HomeCameraApp extends StatelessWidget {
  const HomeCameraApp({super.key});

  @override
  Widget build(BuildContext context) => KyeobomAdsRuntime(
        child: MaterialApp(
          title: '켜봄',
        debugShowCheckedModeBanner: false,
        theme: KyeobomTheme.light,
        // Render FCM health warnings over full-screen landscape video.
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            if (child != null) child,
            const Positioned(
              top: 0, left: 0, right: 0,
              child: HealthPushForegroundBanner(),
            ),
          ],
        ),
        routes: {
          '/roles': (_) => const RoleSelectionScreen(),
          '/station': (_) => const StationScreen(),
        },
        home: Firebase.apps.isEmpty
            ? const Scaffold(
                body: Center(
                  child: Text('Firebase 설정 필요: flutterfire configure 후 앱을 재빌드하세요'),
                ),
              )
            : FirebaseAuth.instance.currentUser == null
                ? const LoginScreen()
                : FirebaseAuth.instance.currentUser!.isAnonymous
                    ? const StationScreen()
                    : const RoleSelectionScreen(),
        ),
      );
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _openStation(BuildContext context) async {
    final confirmed = await showKyeobomStationStartDialog(context);
    if (confirmed != true || !context.mounted) return;
    try {
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] role selection: station sign-in begin');
      }
      // Revoke the previous viewer registration BEFORE Auth switches to an
      // anonymous station identity; afterwards its token document is inaccessible.
      if (FirebaseAuth.instance.currentUser?.isAnonymous == false) {
        await HealthPushMessaging.instance.signOut();
      }
      await RemoteControl.instance.signInStationAnonymously();
      if (kDebugMode) {
        debugPrint('[kyeobom/qa] role selection: station sign-in success');
      }
      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const StationScreen()),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('거치폰 설정 실패: $error. Firebase 익명 인증을 확인해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Navigator.of(context).canPop()
          ? IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => Navigator.of(context).pop(),
            )
          : const Icon(Icons.videocam_outlined, size: 21),
      title: const Text('기기 역할 선택',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      actions: [
        IconButton(
          tooltip: '로그아웃',
          icon: const Icon(Icons.logout_rounded, size: 19),
          onPressed: () async {
            try {
              if (FirebaseAuth.instance.currentUser?.isAnonymous == true) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('거치폰 인증 초기화'),
                    content: const Text(
                      '이 거치폰에 연결된 뷰어의 접근 권한이 사라지고 '
                      '다음 사용 시 다시 연결해야 합니다. 계속할까요?'),
                    actions: [
                      TextButton(onPressed: () =>
                        Navigator.of(context).pop(false),
                        child: const Text('취소')),
                      FilledButton(onPressed: () =>
                        Navigator.of(context).pop(true),
                        child: const Text('초기화')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                // Revocation is server-enforced before dropping local Auth.
                await RemoteControl.instance.station.delete();
              }
              await HealthPushMessaging.instance.signOut();
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('기기 연결 해제 실패: $error'),
                ));
              }
            }
          },
        ),
        const SizedBox(width: 5),
      ],
    ),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const KyeobomEyebrow('STEP 02 · DEVICE ROLE'),
          const SizedBox(height: 13),
          const Text('이 스마트폰은\n어떻게 사용하실까요?',
            style: TextStyle(color: KyeobomPalette.ink, fontSize: 27,
              height: 1.24, fontWeight: FontWeight.w800,
              letterSpacing: -1)),
          const SizedBox(height: 10),
          const Text('기기의 사용 목적을 선택해 주세요.\n선택 후에도 역할을 바꿀 수 있어요.',
            style: TextStyle(color: KyeobomPalette.muted,
              fontSize: 13, height: 1.5)),
          const SizedBox(height: 25),
          KyeobomRoleCard(
            icon: Icons.videocam_rounded,
            title: '홈캠으로 사용',
            subtitle: '집에 있는 스마트폰을 홈캠으로 사용하고\n필요할 때 다른 스마트폰으로 확인해요.',
            featured: true,
            onTap: () => _openStation(context),
          ),
          const SizedBox(height: 14),
          KyeobomRoleCard(
            icon: Icons.visibility_outlined,
            title: '홈캠 보기',
            subtitle: '다른 기기에 연결된 홈캠의 영상을\n실시간으로 확인할 수 있어요.',
            onTap: () {
              if (FirebaseAuth.instance.currentUser?.isAnonymous == true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('뷰어폰은 이메일 계정으로 로그인해 주세요.'),
                ));
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) =>
                  ViewerPairingGate(viewerBuilder: (_) => const ViewerScreen())),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: KyeobomPalette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded,
                color: KyeobomPalette.blue, size: 19),
              SizedBox(width: 10),
              Expanded(child: Text(
                '안정적인 연결을 위해 홈캠으로 사용할 스마트폰은 '
                '충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
                style: TextStyle(fontSize: 11, height: 1.5,
                  color: KyeobomPalette.muted),
              )),
            ]),
          ),
        ]),
      ),
    ))),
  );
}

class StationScreen extends StatefulWidget {
  const StationScreen({super.key});

  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen>
    with WidgetsBindingObserver {
  static const _screen = MethodChannel('home_camera/screen');
  late final HomeCamWebRtcSession _rtc;
  late final StationMicrophone _microphone;
  late final Future<void> _micSettingsReady;
  final SharedPreferencesAsync _micPreferences = SharedPreferencesAsync();
  static const _micAutoKey = 'station_auto_microphone_when_viewing_v1';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _commands;
  DeviceHealthPublisher? _health;
  String? _healthSyncError;
  DeviceHealthSnapshot? _latestHealth;
  late final EventRecordingController _events;
  late final Future<void> _eventSettingsReady;
  static const _eventAutoKey = 'station_motion_record_opt_in_v1';
  bool _eventEnabled = false;
  bool _eventBusy = false;
  bool _eventRecording = false;
  String? _eventStatus;
  late final BabySoundMonitor _babySound;
  late final Future<void> _babySettingsReady;
  static const _babyAutoKey = 'station_baby_sound_opt_in_v1';
  bool _babyEnabled = false;
  bool _babyBusy = false;
  String? _babyStatus;
  bool _babySourceChanging = false;
  int _babyConsentRevision = 0;
  Future<void> _commandQueue = Future<void>.value();

  String _status = '연결 대기 준비 중';
  String? _lastCommandId;
  bool _foreground = true;
  bool _streaming = false;
  bool _preparingStream = false;
  bool _leaving = false;
  bool _microphoneOn = false;
  bool _microphoneBusy = false;
  bool _micAutoEnabled = false;
  bool _micSettingsBusy = false;
  String? _microphoneMessage;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[kyeobom/qa] station screen: initState entered');
    }
    unawaited(HealthPushMessaging.instance.activateStation());
    _events = EventRecordingController(
      onStatus: (status) {
        if (mounted && !_leaving) setState(() => _eventStatus = status);
      },
      onRecordingChanged: (recording) {
        if (mounted) setState(() => _eventRecording = recording);
      },
    );
    _eventSettingsReady = _loadEventSetting();
    _babySound = BabySoundMonitor(
      enableCryQa: true,
      onCryDetected: () => unawaited(_publishBabyCry()),
      onStatus: (status) {
        if (mounted && !_leaving) setState(() => _babyStatus = status);
      },
      onDetection: (_) {},
    );
    _babySettingsReady = _loadBabySetting();
    _microphone = StationMicrophone(onState: (capturing, message) {
      if (!mounted) return;
      setState(() {
        _microphoneOn = capturing;
        _microphoneMessage = message;
      });
    });
    _micSettingsReady = _loadMicSetting();
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onRemoteEnded: () {
        _commandQueue = _commandQueue.then((_) => _finishStream()).catchError(
          (Object error) {
            if (mounted) setState(() => _status = '종료 처리 오류: $error');
          },
        );
      },
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterWaiting());
    unawaited(_connectCommands());
    _health = DeviceHealthPublisher(
      onSample: _onHealthSample,
      onSyncError: (code) {
        if (!mounted || _healthSyncError == code) return;
        setState(() => _healthSyncError = code);
      },
    );
    _health!.start();
  }



  Future<void> _loadBabySetting() async {
    try {
      final enabled = await _micPreferences.getBool(_babyAutoKey) ?? false;
      _babySound.setEnabled(enabled);
      if (mounted) setState(() => _babyEnabled = enabled);
    } catch (error) {
      if (mounted) setState(() => _babyStatus = '베이비 모드 설정 읽기 오류: $error');
    }
  }

  Future<void> _resumeBabyMonitoring() async {
    if (!mounted || _leaving || !_foreground || _babySourceChanging ||
        !_babyEnabled || !_babySound.enabled ||
        _latestHealth?.shouldStopVideo == true) return;
    try {
      await _babySound.start(webRtcTrackId: _microphone.audioTrackId);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _babyStatus = '베이비 소리 감지 시작 실패: $error');
      }
    }
  }

  Future<void> _publishBabyCry() async {
    final revision = _babyConsentRevision;
    final detectedAt = DateTime.now();
    if (!mounted || _leaving || !_foreground || !_babyEnabled ||
        !_babySound.enabled) return;
    try {
      final control = RemoteControl.instance;
      if (!control.isStationIdentity) return;
      final station = control.station;
      final snapshot = await station.get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final viewerUid = snapshot.data()?['viewerUid'];
      if (viewerUid is! String || viewerUid.isEmpty ||
          snapshot.data()?['onlineHint'] != true ||
          !mounted || _leaving || !_foreground || !_babyEnabled ||
          !_babySound.enabled || revision != _babyConsentRevision ||
          FirebaseAuth.instance.currentUser?.uid != station.id) return;
      await station.collection('telemetry').doc('babyCry').set({
        'viewerUid': viewerUid,
        'detectedAt': Timestamp.fromDate(detectedAt),
        'receivedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      if (mounted && !_leaving && _babyEnabled) {
        setState(() => _babyStatus = '알림 전송 실패 · 인터넷 연결을 확인해 주세요.');
      }
    }
  }

  Future<void> _setBabyEnabled(bool enabled) async {
    if (_babyBusy || _leaving || (enabled && _babySourceChanging)) return;
    ++_babyConsentRevision;
    setState(() => _babyBusy = true);
    try {
      // Permission is requested ONLY after deliberate station-side opt-in.
      // The temporary WebRTC permission track is released immediately.
      if (enabled && !_microphone.isOn) await StationMicrophone.preparePermission();
      _babySound.setEnabled(enabled);
      if (!enabled) await _babySound.stop();
      await _micPreferences.setBool(_babyAutoKey, enabled);
      if (mounted) setState(() {
        _babyEnabled = enabled;
        _babyStatus = enabled ? '아기 울음 감지 준비 중' : null;
      });
      if (enabled) await _resumeBabyMonitoring();
    } catch (error) {
      _babySound.setEnabled(false);
      try { await _babySound.stop(); } catch (_) {}
      try { await _micPreferences.setBool(_babyAutoKey, false); } catch (_) {}
      if (mounted) setState(() {
        _babyEnabled = false;
        _babyStatus = '베이비 모드 실행 실패: $error';
      });
    } finally {
      if (mounted) setState(() => _babyBusy = false);
    }
  }

  Future<void> _loadEventSetting() async {
    try {
      final enabled = await _micPreferences.getBool(_eventAutoKey) ?? false;
      _events.setEnabled(enabled);
      if (mounted) setState(() => _eventEnabled = enabled);
    } catch (error) {
      if (mounted) setState(() => _eventStatus = '녹화 설정 확인 실패: $error');
    }
  }

  Future<void> _setEventEnabled(bool enabled) async {
    if (_leaving || _eventBusy) return;
    setState(() => _eventBusy = true);
    try {
      await _micPreferences.setBool(_eventAutoKey, enabled);
      _events.setEnabled(enabled);
      if (!enabled) {
        await _events.stop();
      } else if (_streaming && _latestHealth?.shouldReduceVideo != true) {
        await _events.start(_rtc.stationVideoTrack);
      }
      if (mounted) setState(() {
        _eventEnabled = enabled;
        _eventStatus = enabled
            ? '움직임이 감지되면 20초 영상이 거치폰에만 저장됩니다'
            : '이벤트 자동 녹화가 꺼졌어요';
      });
    } catch (error) {
      if (mounted) setState(() => _eventStatus = '자동 녹화 설정 실패: $error');
    } finally {
      if (mounted) setState(() => _eventBusy = false);
    }
  }

  Future<void> _openEventClips() async {
    if (_leaving || _streaming) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const EventClipsScreen()));
  }

  Future<void> _openPairingDialog() async {
    if (_leaving) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StationPairingDialog(stopStream: _finishStream),
    );
  }

  void _onHealthSample(DeviceHealthSnapshot snapshot) {
    if (!mounted || _leaving) return;
    setState(() => _latestHealth = snapshot);
    if (snapshot.shouldStopVideo) {
      unawaited(_babySound.stop().catchError((Object _) {}));
    } else if (_babyEnabled) {
      unawaited(_resumeBabyMonitoring());
    }
    // Recording has a lower priority than thermals, battery and video.
    if (snapshot.shouldReduceVideo) {
      unawaited(_events.stop());
    } else if (_streaming && _eventEnabled) {
      unawaited(_events.start(_rtc.stationVideoTrack));
    }

    if (snapshot.shouldStopVideo && _rtc.isRunning) {
      _commandQueue = _commandQueue.then((_) async {
        if (!mounted || _leaving || !_rtc.isRunning) return;
        await _finishStream();
        if (mounted) setState(() => _status = snapshot.warning);
      }).catchError((Object error) {
        if (mounted) setState(() => _status = '기기 보호 처리 오류: $error');
      });
    } else if (_streaming && _rtc.isRunning &&
        _rtc.isVideoReduced != snapshot.shouldReduceVideo) {
      // Serialized with start/stop requests: quality adjustment does not
      // create a new peer, restart the camera, or touch the microphone.
      _commandQueue = _commandQueue.then((_) async {
        if (!mounted || _leaving || !_rtc.isRunning) return;
        final applied = await _rtc.setReducedQuality(
          snapshot.shouldReduceVideo,
        );
        if (mounted && applied) {
          setState(() => _status = snapshot.shouldReduceVideo
              ? '배터리·발열 보호 · 저화질 송출 중'
              : '기기 상태 회복 · 기본 화질로 복귀');
        }
        if (mounted && !applied) {
          setState(() => _status =
              '기기에서 실시간 화질 전환을 지원하지 않아요');
        }
      }).catchError((Object error) {
        if (mounted) setState(() => _status = '품질 조절 오류: $error');
      });
    }
  }

  Future<void> _enterWaiting() async {
    try {
      await _screen.invokeMethod<void>('enableWaitingMode');
      if (mounted && !_streaming) {
        setState(() => _status = '연결 대기 중');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '화면 유지 오류: $error');
    }
  }

  Future<void> _loadMicSetting() async {
    try {
      final enabled = await _micPreferences.getBool(_micAutoKey) ?? false;
      if (mounted) setState(() => _micAutoEnabled = enabled);
    } catch (error) {
      if (mounted) {
        setState(() => _microphoneMessage = '마이크 설정 읽기 실패: $error');
      }
    }
  }

  /// This consent is configured on the station device while a person is there.
  /// Permission capture is stopped immediately; no idle microphone remains on.
  Future<void> _setMicAutoEnabled(bool enabled) async {
    if (_micSettingsBusy || _streaming || _leaving) return;
    setState(() => _micSettingsBusy = true);
    try {
      if (enabled) {
        await StationMicrophone.preparePermission();
      }
      await _micPreferences.setBool(_micAutoKey, enabled);
      if (mounted) {
        setState(() {
          _micAutoEnabled = enabled;
          _microphoneMessage = enabled
              ? '원격 영상 시작 시 이 거치폰 마이크가 자동으로 켜집니다'
              : '원격 마이크 자동 시작을 해제했습니다';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _microphoneMessage = '거치폰 마이크 권한 오류: $error');
      }
    } finally {
      if (mounted) setState(() => _micSettingsBusy = false);
    }
  }

  Future<void> _connectCommands() async {
    try {
      await _micSettingsReady;
      await _eventSettingsReady;
      await _babySettingsReady;
      await RemoteControl.instance.startStation();
      unawaited(_resumeBabyMonitoring());
      if (!mounted || _leaving) return;
      _commands = RemoteControl.instance.watch().listen((snapshot) {
        final data = snapshot.data();
        if (!mounted || _leaving || data == null) return;
        final id = data['commandId'] as String? ?? '';
        if (id.isEmpty || id == _lastCommandId) return;
        _lastCommandId = id;
        _commandQueue = _commandQueue.then((_) => _handleCommand(data))
            .catchError((Object error) {
          if (mounted) setState(() => _status = '원격 요청 오류: $error');
        });
      }, onError: (Object error) {
        if (mounted) setState(() => _status = 'Firebase 연결 오류: $error');
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Firebase 연결 오류: $error');
    }
  }

  Future<void> _handleCommand(Map<String, dynamic> data) async {
    if (!mounted || _leaving) return;
    final command = data['command'] as String? ?? 'idle';
    final id = data['commandId'] as String? ?? '';
    final sessionId = data['sessionId'] as String? ?? '';

    if (command == 'stop') {
      // Ignore delayed stop commands from an older session.
      if (sessionId != _rtc.sessionId) return;
      await _finishStream();
      await RemoteControl.instance.acknowledge(id, 'camera_off');
      return;
    }
    if (command != 'start' || !_foreground) return;

    final requestedAt = data['updatedAt'];
    if (requestedAt is Timestamp &&
        DateTime.now().difference(requestedAt.toDate()) >
            const Duration(seconds: 60)) {
      await RemoteControl.instance.acknowledge(id, 'expired_request');
      return;
    }
    if (sessionId.isEmpty) return;

    // Safety gate before opening a new camera. No camera or microphone is
    // ever started when the OS reports critical thermal/battery conditions.
    final risk = _latestHealth;
    if (risk != null && risk.shouldStopVideo) {
      try {
        await RemoteControl.instance.session(sessionId).set({
          'state': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
          'healthReason': risk.warning,
        }, SetOptions(merge: true));
        await RemoteControl.instance.acknowledge(id, 'health_protection');
      } catch (_) {
        // Never open the camera if protection signalling fails.
      }
      if (mounted) setState(() => _status = risk.warning);
      return;
    }

    _preparingStream = true;
    try {
      if (mounted) setState(() => _status = '원격 연결 준비 중');
      // Video-only WebRTC never opens an audio track. Keep baby capture on.
      if (_rtc.isRunning && _rtc.sessionId != sessionId) {
        _babySourceChanging = true;
        await _babySound.stop();
        // Finalize any clip BEFORE the previous camera track is released.
        await _events.stop();
        await _microphone.disable();
        await _rtc.end();
      }
      await _rtc.startStation(
        sessionId,
        reducedQuality: _latestHealth?.shouldReduceVideo ?? false,
      );
      if (!mounted || _leaving || !_foreground) {
        await _rtc.end();
        unawaited(_resumeBabyMonitoring());
        return;
      }
      setState(() {
        _streaming = true;
        _status = '후면 카메라 송출 중 · 마이크 OFF';
      });
      // Opt-in only, and only on a live camera track. A recorder error must
      // never block signaling or live viewing.
      if (_eventEnabled && _latestHealth?.shouldReduceVideo != true) {
        unawaited(_events.start(_rtc.stationVideoTrack).catchError(
          (Object error) {
            if (mounted) {
              setState(() => _eventStatus = '자동 녹화 시작 실패: $error');
            }
          },
        ));
      }
      await RemoteControl.instance.acknowledge(id, 'answer_ready');
      if (_micAutoEnabled && _streaming && _rtc.sessionId == sessionId) {
        // Station-side opt-in only; viewer has no microphone capture.
        // Audio failure is isolated and cannot tear down the video peer.
        unawaited(_toggleStationMicrophone());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _streaming = false;
          _status = '송출 시작 실패: $error';
        });
      }
      await RemoteControl.instance.acknowledge(id, 'error: $error');
    } finally {
      _preparingStream = false;
      _babySourceChanging = false;
      if (mounted && _foreground) unawaited(_resumeBabyMonitoring());
    }
  }

  Future<void> _toggleStationMicrophone() async {
    if (_microphoneBusy || _leaving || !_streaming) return;
    final sessionId = _rtc.sessionId;
    if (sessionId == null) return;
    setState(() => _microphoneBusy = true);
    _babySourceChanging = true;
    try {
      await _babySound.stop();
      if (_microphone.isOn) {
        await _microphone.disable();
      } else {
        await _microphone.enable(sessionId);
      }
    } catch (error) {
      if (mounted) setState(() => _microphoneMessage = '마이크 오류: $error');
    } finally {
      _babySourceChanging = false;
      if (mounted) setState(() => _microphoneBusy = false);
      await _resumeBabyMonitoring();
    }
  }

  Future<void> _finishStream() async {
    _babySourceChanging = true;
    try {
      await _events.stop();
      if (_microphone.isOn || _microphoneBusy) await _babySound.stop();
      await _microphone.disable();
      if (_rtc.isRunning) await _rtc.end();
    } finally {
      _babySourceChanging = false;
    }
    if (mounted && !_leaving) {
      setState(() {
        _streaming = false;
        _microphoneOn = false;
        _microphoneMessage = null;
        _status = '연결 대기 중';
      });
      // Resume opt-in listening only once camera/audio tracks are closed.
      unawaited(_resumeBabyMonitoring());
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _commands?.cancel();
    _health?.stop();
    try {
      await _babySound.stop();
      await _events.stop();
      await _microphone.disable();
      await _rtc.end();
      await RemoteControl.instance.stopStation();
    } finally {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const RoleSelectionScreen()),
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // iOS microphone permission sheet may temporarily set "inactive".
    // Stop only when actually backgrounded.
    final background = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (background && !_leaving) {
      unawaited(_babySound.stop().catchError((Object _) {}));
      _health?.stop();
      if (mounted) {
        setState(() => _status = '앱 비활성화 · 영상 송출 중단');
      }
      _commandQueue = _commandQueue.then((_) => _finishStream()).catchError(
        (Object error) {
          if (mounted) setState(() => _status = '종료 오류: $error');
        },
      );
    } else if (_foreground && mounted) {
      _health?.start();
      unawaited(_health?.refresh());
      if (!_streaming) {
        setState(() => _status = '연결 대기 중');
        unawaited(_resumeBabyMonitoring());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _health?.stop();
    unawaited(_babySound.dispose().catchError((Object _) {}));
    // Native camera teardown remains deferred; finalize video first.
    unawaited(_events.stop().then((_) => _rtc.end(notifyRemote: !_leaving)));
    unawaited(_commands?.cancel());
    unawaited(_microphone.disable());
    if (!_leaving) unawaited(RemoteControl.instance.stopStation());
    unawaited(_screen.invokeMethod<void>('disableWaitingMode'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_leave());
        },
        child: KyeobomStationView(
          status: _status,
          streaming: _streaming,
          microphoneOn: _microphoneOn,
          microphoneBusy: _microphoneBusy,
          microphoneMessage: _microphoneMessage,
          healthSyncError: _healthSyncError,
          healthSummary: _latestHealth == null
              ? '기기 상태 확인 중'
              : '배터리 ${_latestHealth!.batteryLabel} · 발열 ${_latestHealth!.heatLabel}',
          healthWarning: _latestHealth?.warning,
          eventRecordingEnabled: _eventEnabled,
          eventRecordingBusy: _eventBusy,
          recordingEvent: _eventRecording,
          eventRecordingStatus: _eventStatus,
          onEventRecordingChanged: (enabled) =>
              unawaited(_setEventEnabled(enabled)),
          onViewEventClips: () => unawaited(_openEventClips()),
          babyEnabled: _babyEnabled,
          babyBusy: _babyBusy,
          babyRunning: _babySound.running,
          babyStatus: _babyStatus,
          onBabyChanged: (enabled) => unawaited(_setBabyEnabled(enabled)),
          autoMicrophoneEnabled: _micAutoEnabled,
          autoMicrophoneBusy: _micSettingsBusy,
          onAutoMicrophoneChanged: (enabled) =>
              unawaited(_setMicAutoEnabled(enabled)),
          leaving: _leaving,
          onLeave: () => unawaited(_leave()),
          onToggleMicrophone: () => unawaited(_toggleStationMicrophone()),
          onManagePairing: () => unawaited(_openPairingDialog()),
        ),
      );
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with WidgetsBindingObserver {
  static const _orientationChannel = MethodChannel('home_camera/screen');
  Timer? _orientationTimer;
  bool _orientationQueryBusy = false;
  bool _landscapeRight = false;
  late final HomeCamWebRtcSession _rtc;
  late final ViewerAudio _viewerAudio;
  bool _remoteAudioOn = false;
  String? _remoteAudioMessage;
  String _status = '실시간 보기를 누르면 원격 연결합니다';
  bool _busy = false;
  bool _watching = false;
  bool _leaving = false;
  bool _landscapeLocked = false;
  DateTime? _viewStartedAt;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;
  bool _userStopped = false;
  bool _viewerInBackground = false;

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect() {
    if (!mounted || !_watching || _busy || _reconnecting ||
        _reconnectTimer != null) return;
    if (!HomeCamRecoveryPolicy.shouldRetry(
      userStopped: _userStopped,
      leaving: _leaving,
      inBackground: _viewerInBackground,
      attemptedRetries: _reconnectAttempts,
    )) {
      if (mounted && !_userStopped && !_leaving && !_viewerInBackground) {
        setState(() => _status = '연결을 복구하지 못했어요. 종료 후 다시 시작해 주세요.');
      }
      return;
    }
    final delay = HomeCamRecoveryPolicy.retryDelay(_reconnectAttempts)!;
    _reconnectAttempts++;
    setState(() =>
      _status = '연결이 끊겼어요 · 재연결 ${_reconnectAttempts}/3 준비 중');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_retryConnection());
    });
  }

  Future<void> _retryConnection() async {
    if (_userStopped || _leaving || _viewerInBackground ||
        !_watching || _reconnecting || _busy) return;
    _reconnecting = true;
    setState(() => _status = '홈캠 자동 재연결 중...');
    var failed = false;
    try {
      await _viewerAudio.detach();
      // Restart as a fresh session; the current signaling flow handles a
      // single offer/answer, so an in-place ICE restart would be unsafe.
      await _rtc.end();
      await _rtc.startViewer();
      if (_userStopped || _leaving || _viewerInBackground || !mounted) {
        await _rtc.end();
        return;
      }
      try {
        await _viewerAudio.attach(_rtc.sessionId!);
      } catch (error) {
        if (mounted) setState(() => _remoteAudioMessage = '소리 연결 재시도: $error');
      }
      if (mounted) setState(() => _status = '홈캠 재연결 요청 완료');
    } catch (error) {
      failed = true;
      if (mounted) setState(() => _status = '자동 재연결 오류: $error');
    } finally {
      _reconnecting = false;
    }
    if (failed) _scheduleReconnect();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(HealthPushMessaging.instance.activateViewer());
    _viewerAudio = ViewerAudio(onState: (receiving, message) {
      if (!mounted) return;
      if (_remoteAudioOn != receiving || _remoteAudioMessage != message) {
        setState(() {
          _remoteAudioOn = receiving;
          _remoteAudioMessage = message;
        });
      }
    });
    _rtc = HomeCamWebRtcSession(
      onStatus: (value) {
        if (mounted) setState(() => _status = value);
      },
      onRemoteEnded: () => unawaited(_stop(notifyRemote: false)),
      onConnectionLost: _scheduleReconnect,
      onConnectionEstablished: () {
        _reconnectAttempts = 0;
        _cancelReconnect();
      },
    );
  }

  /// Allow both horizontal orientations so a physical 180° phone rotation
  /// also rotates all Flutter controls, system text, and the video surface.
  Future<void> _enterLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _landscapeLocked = true;
    _orientationTimer?.cancel();
    _orientationTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => unawaited(_refreshDisplaySide()),
    );
    unawaited(_refreshDisplaySide());
  }

  /// Width/height are unchanged when landscapeLeft flips to landscapeRight.
  /// Ask native UI orientation while viewing so video pixel correction flips
  /// with the physical device, not only the overlay buttons.
  Future<void> _refreshDisplaySide() async {
    if (_orientationQueryBusy || !_landscapeLocked || !mounted) return;
    _orientationQueryBusy = true;
    try {
      final side = await _orientationChannel.invokeMethod<String>(
        'getViewerLandscapeSide',
      );
      if (!mounted || !_landscapeLocked) return;
      if (side == 'left' || side == 'right') {
        final right = side == 'right';
        if (_landscapeRight != right) {
          setState(() => _landscapeRight = right);
        }
      }
    } catch (_) {
      // Continue with last known side; orientation cannot break video.
    } finally {
      _orientationQueryBusy = false;
    }
  }

  /// Return to portrait first, then release the orientation restriction.
  /// No permanent phone setting is changed.
  Future<void> _restoreOrientation() async {
    _orientationTimer?.cancel();
    _orientationTimer = null;
    if (!_landscapeLocked) return;
    _landscapeLocked = false;
    _landscapeRight = false;
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _start() async {
    if (_busy || _watching || _leaving) return;
    _userStopped = false;
    _viewerInBackground = false;
    _reconnectAttempts = 0;
    _cancelReconnect();
    setState(() {
      _busy = true;
      _status = '거치폰 연결 요청 중';
    });

    KyeobomFullscreenAds.instance.beginLive();
    try {
      await _rtc.startViewer();
      if (!mounted || _leaving) {
        await _rtc.end();
        return;
      }
      _viewStartedAt = DateTime.now();
      setState(() => _watching = true);
      // Audio listens independently; it must never break the video session.
      try {
        await _viewerAudio.attach(_rtc.sessionId!);
      } catch (error) {
        if (mounted) setState(() => _remoteAudioMessage = '오디오 준비 오류: $error');
      }

      try {
        await _enterLandscape();
      } catch (error) {
        if (mounted) {
          setState(() => _status = '영상 요청 완료 · 가로모드 전환 실패: $error');
        }
      }
    } catch (error) {
      KyeobomFullscreenAds.instance.leaveViewer();
      if (mounted) setState(() => _status = '영상 연결 오류: $error');
      await _restoreOrientation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({
    bool notifyRemote = true,
    bool userPressedStop = false,
  }) async {
    if (_busy || _leaving) return;
    _userStopped = true;
    _cancelReconnect();
    final id = _rtc.sessionId;
    final viewingFor = DateTime.now().difference(
      _viewStartedAt ?? DateTime.now(),
    );
    _viewStartedAt = null;
    var transportStopped = false;
    setState(() {
      _busy = true;
      _watching = false;
    });

    try {
      await _viewerAudio.detach();
      await _rtc.end(notifyRemote: notifyRemote);
      transportStopped = true;
      if (notifyRemote && id != null) {
        await RemoteControl.instance.requestStop(id);
      }
      if (mounted) {
        setState(() => _status = '영상 종료 · 거치폰 카메라 정리 요청 완료');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '영상 종료 오류: $error');
    } finally {
      try {
        await _restoreOrientation();
      } catch (error) {
        if (mounted) setState(() => _status = '화면 방향 복구 오류: $error');
      }
      if (mounted) {
        setState(() => _busy = false);
        // Schedule after the portrait dashboard frame: do not block video
        // release, do not show over camera, and never monetize app exit.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && transportStopped && !_rtc.isRunning &&
              !_leaving && !_watching) {
            unawaited(KyeobomFullscreenAds.instance.completedLiveView(
              viewedFor: viewingFor,
              explicitStop: userPressedStop,
            ));
          }
        });
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _userStopped = true;
    _cancelReconnect();
    KyeobomFullscreenAds.instance.leaveViewer();
    setState(() => _leaving = true);
    final id = _rtc.sessionId;

    try {
      await _viewerAudio.detach();
      await _rtc.end();
      if (id != null) {
        await RemoteControl.instance.requestStop(id);
      }
    } catch (error) {
      if (mounted) setState(() => _status = '연결 종료 오류: $error');
    } finally {
      try {
        await _restoreOrientation();
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    _viewerInBackground = background;
    if (background) {
      _cancelReconnect();
      KyeobomFullscreenAds.instance.appBackgrounded();
    } else if (state == AppLifecycleState.resumed && !_watching && !_busy) {
      unawaited(KyeobomFullscreenAds.instance.appForegrounded());
    }
    if (background && !_leaving && _watching && !_busy) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    KyeobomFullscreenAds.instance.leaveViewer();
    _cancelReconnect();
    _orientationTimer?.cancel();
    unawaited(_viewerAudio.detach());
    unawaited(_rtc.end());
    if (_landscapeLocked) unawaited(_restoreOrientation());
    super.dispose();
  }

  Widget _video() {
    final renderer = _rtc.renderer;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _watching && renderer != null
          ? AnimatedBuilder(
              animation: renderer,
              builder: (context, _) {
                final landscape = MediaQuery.orientationOf(context) ==
                    Orientation.landscape;
                final quarterTurns = videoQuarterTurns(
                  viewerLandscape: landscape,
                  landscapeRight: _landscapeRight,
                );
                return ViewerVideoControls(
                  video: RotatedBox(
                    quarterTurns: quarterTurns,
                    child: RTCVideoView(
                      renderer,
                      // Cover the entire rotated viewport; contain caused
                      // the narrow upright strip with huge black side bars.
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                );
              },
            )
          : const Icon(Icons.videocam_off_outlined,
              size: 60, color: Colors.white38),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: KyeobomViewerView(
        video: _video(),
        status: _status,
        watching: _watching,
        busy: _busy,
        leaving: _leaving,
        landscape: landscape,
        remoteAudioOn: _remoteAudioOn,
        remoteAudioMessage: _remoteAudioMessage,
        onBack: () => unawaited(_leave()),
        onStart: () => unawaited(_start()),
        onStop: () => unawaited(_stop(userPressedStop: true)),
      ),
    );
  }
}
