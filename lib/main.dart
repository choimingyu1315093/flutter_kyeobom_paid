import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RemoteControl.instance.initialize();
  } catch (_) {
    // A clear setup prompt is shown below when Firebase is unavailable.
  }
  runApp(const HomeCameraApp());
}

class HomeCameraApp extends StatelessWidget {
  const HomeCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '켜봄',
        debugShowCheckedModeBanner: false,
        theme: KyeobomTheme.light,
        routes: {'/roles': (_) => const RoleSelectionScreen()},
        home: Firebase.apps.isEmpty
            ? const Scaffold(
                body: Center(
                  child: Text('Firebase 설정 필요: flutterfire configure 후 앱을 재빌드하세요'),
                ),
              )
            : FirebaseAuth.instance.currentUser == null
                ? const LoginScreen()
                : const RoleSelectionScreen(),
      );
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _openStation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('홈캠 대기 모드가 시작됩니다.'),
        content: const Text(
          '화면은 어둡게 유지되며 자동으로 잠기지 않습니다.\n\n'
          '안정적인 원격 연결을 위해 충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('대기 시작'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StationScreen()),
    );
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ViewerScreen()),
            ),
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
  Future<void> _commandQueue = Future<void>.value();

  String _status = '연결 대기 준비 중';
  String? _lastCommandId;
  bool _foreground = true;
  bool _streaming = false;
  bool _leaving = false;
  bool _microphoneOn = false;
  bool _microphoneBusy = false;
  bool _micAutoEnabled = false;
  bool _micSettingsBusy = false;
  String? _microphoneMessage;

  @override
  void initState() {
    super.initState();
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
      await RemoteControl.instance.startStation();
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

    try {
      if (mounted) setState(() => _status = '원격 연결 준비 중');
      if (_rtc.isRunning && _rtc.sessionId != sessionId) {
        // Always release any audio from the previous viewer first.
        await _microphone.disable();
        await _rtc.end();
      }
      await _rtc.startStation(sessionId);
      if (!mounted || _leaving || !_foreground) {
        await _rtc.end();
        return;
      }
      setState(() {
        _streaming = true;
        _status = '후면 카메라 송출 중 · 마이크 OFF';
      });
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
    }
  }

  Future<void> _toggleStationMicrophone() async {
    if (_microphoneBusy || _leaving || !_streaming) return;
    final sessionId = _rtc.sessionId;
    if (sessionId == null) return;
    setState(() => _microphoneBusy = true);
    try {
      if (_microphone.isOn) {
        await _microphone.disable();
      } else {
        await _microphone.enable(sessionId);
      }
    } catch (error) {
      if (mounted) setState(() => _microphoneMessage = '마이크 오류: $error');
    } finally {
      if (mounted) setState(() => _microphoneBusy = false);
    }
  }

  Future<void> _finishStream() async {
    await _microphone.disable();
    if (_rtc.isRunning) await _rtc.end();
    if (mounted && !_leaving) {
      setState(() {
        _streaming = false;
        _microphoneOn = false;
        _microphoneMessage = null;
        _status = '연결 대기 중';
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _commands?.cancel();
    try {
      await _microphone.disable();
      await _rtc.end();
      await RemoteControl.instance.stopStation();
    } finally {
      if (mounted) Navigator.of(context).pop();
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
      if (mounted) {
        setState(() => _status = '앱 비활성화 · 영상 송출 중단');
      }
      _commandQueue = _commandQueue.then((_) => _finishStream()).catchError(
        (Object error) {
          if (mounted) setState(() => _status = '종료 오류: $error');
        },
      );
    } else if (_foreground && !_streaming && mounted) {
      setState(() => _status = '연결 대기 중');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_commands?.cancel());
    unawaited(_microphone.disable());
    unawaited(_rtc.end(notifyRemote: !_leaving));
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
          autoMicrophoneEnabled: _micAutoEnabled,
          autoMicrophoneBusy: _micSettingsBusy,
          onAutoMicrophoneChanged: (enabled) =>
              unawaited(_setMicAutoEnabled(enabled)),
          leaving: _leaving,
          onLeave: () => unawaited(_leave()),
          onToggleMicrophone: () => unawaited(_toggleStationMicrophone()),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    setState(() {
      _busy = true;
      _status = '거치폰 연결 요청 중';
    });

    try {
      await _rtc.startViewer();
      if (!mounted || _leaving) {
        await _rtc.end();
        return;
      }
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
      if (mounted) setState(() => _status = '영상 연결 오류: $error');
      await _restoreOrientation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({bool notifyRemote = true}) async {
    if (_busy || _leaving) return;
    final id = _rtc.sessionId;
    setState(() {
      _busy = true;
      _watching = false;
    });

    try {
      await _viewerAudio.detach();
      await _rtc.end(notifyRemote: notifyRemote);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
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
    if (background && !_leaving && _watching && !_busy) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        onStop: () => unawaited(_stop()),
      ),
    );
  }
}
