import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'remote_control.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await RemoteControl.instance.initialize(); } catch (_) { /* setup shown in app */ }
  runApp(const HomeCameraApp());
}

class HomeCameraApp extends StatelessWidget {
  const HomeCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Home Camera P0',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        routes: {'/roles': (_) => const RoleSelectionScreen()},
        home: Firebase.apps.isEmpty
          ? const Scaffold(body: Center(child: Text('Firebase 설정 필요: flutterfire configure 실행 후 재빌드')))
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
        appBar: AppBar(title: const Text('Home Camera · P0')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('이 기기의 역할을 선택하세요',
                    style: TextStyle(fontSize: 22)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.videocam_off),
                  label: const Text('거치폰 · 카메라 대기'),
                  onPressed: () => _openStation(context),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('뷰어폰 · 실시간 보기'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ViewerScreen()),
                  ),
                ),
              ]),
            ),
          ),
        ),
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
  String _status = '대기 화면 준비 중';
  bool _active = false;
  CameraController? _camera;
  String? _cameraError;
  bool _cameraBusy = false;
  StreamSubscription<dynamic>? _remoteSubscription;
  String? _lastCommandId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startWaiting();
    _connectRemote();
  }

  Future<void> _connectRemote() async {
    try {
      await RemoteControl.instance.startStation();
      _remoteSubscription = RemoteControl.instance.watch().listen((snapshot) async {
        if (!mounted || !snapshot.exists) return;
        final data = snapshot.data()!;
        final id = data['commandId'] as String? ?? '';
        final command = data['command'] as String? ?? 'idle';
        if (id.isEmpty || id == _lastCommandId) return;
        _lastCommandId = id;
        if (command != 'start' && command != 'stop') return;
        try {
          if (command == 'start' && _camera == null) await _toggleCamera();
          if (command == 'stop' && _camera != null) await _toggleCamera();
          await RemoteControl.instance.acknowledge(id,
            _cameraError != null ? 'error: $_cameraError' : (_camera == null ? 'camera_off' : 'camera_on'));
        } catch (error) {
          await RemoteControl.instance.acknowledge(id, 'error: $error');
        }
      }, onError: (Object error) {
        if (mounted) setState(() => _status = '원격 연결 오류: $error');
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Firebase 연결 오류: $error');
    }
  }

  Future<void> _startWaiting() async {
    try {
      await _screen.invokeMethod<void>('enableWaitingMode');
      if (!mounted) return;
      setState(() {
        _active = true;
        _status = '연결 대기 중';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _status = '화면 유지 설정 실패: ${error.message}');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _status = '네이티브 화면 유지 기능을 설치해야 합니다');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _status = state == AppLifecycleState.resumed
          ? (_active ? '연결 대기 중' : '화면 유지 미설정')
          : '앱 비활성화 · 원격 연결 보장 안 됨';
    });
  }

  Future<void> _toggleCamera() async {
    if (_cameraBusy) return;
    setState(() => _cameraBusy = true);
    try {
      if (_camera != null) {
        final old = _camera!;
        setState(() => _camera = null);
        await old.dispose();
      } else {
        final devices = await availableCameras();
        final rear = devices.where(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        if (rear.isEmpty) throw StateError('후면 카메라를 찾을 수 없습니다');
        final controller = CameraController(
          rear.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _camera = controller;
          _cameraError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _cameraError = '$error');
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remoteSubscription?.cancel();
    RemoteControl.instance.stopStation();
    _camera?.dispose();
    _screen.invokeMethod<void>('disableWaitingMode');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam_off_outlined,
                    size: 36, color: Colors.white30),
                const SizedBox(height: 16),
                Text(_status,
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 12),
                const Text('카메라 OFF · 마이크 OFF · 녹화 OFF',
                    style: TextStyle(color: Colors.white30, fontSize: 12)),
                const SizedBox(height: 18),
                if (_camera != null && _camera!.value.isInitialized)
                  SizedBox(
                    width: 220,
                    height: 280,
                    child: CameraPreview(_camera!),
                  ),
                if (_cameraError != null)
                  Text(_cameraError!,
                      style: const TextStyle(color: Colors.orangeAccent)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _cameraBusy ? null : _toggleCamera,
                  child: Text(_camera == null
                      ? '후면 카메라 로컬 테스트 (P1)'
                      : '카메라 끄기'),
                ),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('대기 종료'),
                ),
              ]),
            ),
          ),
        ),
      );
}

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('뷰어 · 원격 제어 P2')),
    body: StreamBuilder(
      stream: RemoteControl.instance.watch(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status = data?['status'] ?? '응답 대기';
        final online = data?['onlineHint'] == true;
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('거치폰: ${online ? "대기 중 (최근 상태)" : "대기 중 아님"}'),
          Text('마지막 응답: $status'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              try { await RemoteControl.instance.send('start'); }
              catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
            },
            child: const Text('원격 후면 카메라 켜기'),
          ),
          OutlinedButton(
            onPressed: () async {
              try { await RemoteControl.instance.send('stop'); }
              catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
            },
            child: const Text('원격 카메라 끄기'),
          ),
          const Text('P2: 명령 제어만 구현. 영상 전송은 아직 없음.'),
        ]));
      },
    ),
  );
}
