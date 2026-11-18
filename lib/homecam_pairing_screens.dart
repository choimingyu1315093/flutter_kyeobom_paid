import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'homecam_pairing_qr.dart';
import 'remote_control.dart';

/// Station owner approval stays reachable even on compact phones and with
/// larger accessibility text. Buttons intentionally do not share a Row.
class StationPairingApprovalActions extends StatelessWidget {
  const StationPairingApprovalActions({
    super.key,
    required this.onApprove,
    required this.onReject,
    required this.busy,
  });

  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const Key('kyeobom-approve-pairing'),
            onPressed: busy ? null : onApprove,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(busy ? '처리 중...' : '이 계정 연결 승인'),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('kyeobom-reject-pairing'),
            onPressed: busy ? null : onReject,
            child: const Text('연결 요청 거절'),
          ),
        ],
      );
}

/// The station holds a unique anonymous Auth identity, and must explicitly
/// approve the pending request from a separate viewer account.
class StationPairingDialog extends StatefulWidget {
  const StationPairingDialog({super.key, required this.stopStream});
  final Future<void> Function() stopStream;

  @override
  State<StationPairingDialog> createState() => _StationPairingDialogState();
}

class _StationPairingDialogState extends State<StationPairingDialog> {
  Future<DocumentReference<Map<String, dynamic>>?>? _invite;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renew();
  }

  void _renew() {
    setState(() {
      _error = null;
      _invite = _createIfUnpaired();
    });
  }

  Future<DocumentReference<Map<String, dynamic>>?> _createIfUnpaired() async {
    final station = (await RemoteControl.instance.station.get()).data();
    if ((station?['viewerUid'] as String? ?? '').isNotEmpty) return null;
    return RemoteControl.instance.createPairingInvite();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '기기 연결 처리 오류: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Only the informational region scrolls. Destructive/approval actions stay
  /// in a fixed footer so that users cannot lose them below the dialog edge.
  Widget _panel({required Widget details, Widget? footer}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                child: details,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
              child: footer,
            ),
        ],
      );

  Widget _buildUnpaired(
      AsyncSnapshot<DocumentReference<Map<String, dynamic>>?> inviteSnap) {
    if (inviteSnap.hasError) {
      return _panel(details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('코드 생성 오류: ' + inviteSnap.error.toString()),
          TextButton(
            onPressed: _busy ? null : _renew,
            child: const Text('다시 만들기'),
          ),
        ],
      ));
    }

    if (inviteSnap.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    final ref = inviteSnap.data;
    if (ref == null) {
      // The Firestore station stream will switch to the paired panel.
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, claimSnap) {
        if (claimSnap.hasError) {
          return _panel(details: Text(
            '연결 요청 확인 오류: ' + claimSnap.error.toString()));
        }
        final data = claimSnap.data?.data();
        final pending = data?['status'] == 'pending';
        final email = data?['pendingViewerEmail'] as String? ?? '';
        return _panel(
          details: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '뷰어폰에서 QR코드를 스캔하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  key: const Key('kyeobom-pairing-qr'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: HomeCamPairingQr.encode(ref.id),
                    version: QrVersions.auto,
                    size: 166,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                ref.id,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Center(
                child: TextButton.icon(
                  onPressed: _busy ? null : () async {
                    await Clipboard.setData(ClipboardData(text: ref.id));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('연결 코드를 복사했어요.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('연결 코드 복사'),
                ),
              ),
              const Text(
                '코드는 10분 후 만료돼요. QR 스캔 후에도 거치폰에서 승인해야 연결됩니다.',
                style: TextStyle(fontSize: 12),
              ),
              if (pending) ...[
                const Divider(height: 32),
                const Text(
                  '연결 요청이 도착했습니다',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 9),
                const Text(
                  '요청 계정',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(email),
                const SizedBox(height: 8),
                const Text(
                  '본인이 연결한 뷰어폰 계정이 맞을 때만 승인하세요.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _busy ? null : _renew,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('연결 코드 새로 만들기'),
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
          footer: pending
              ? StationPairingApprovalActions(
                  busy: _busy,
                  onReject: () => _perform(
                    () => RemoteControl.instance.rejectPairing(ref)),
                  onApprove: () => _perform(
                    () => RemoteControl.instance.approvePairing(ref)),
                )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Constrain the entire dialog to the phone's available height. Never let
    // the nested Stream/Future builders dictate an unbounded dialog height.
    final available = media.size.height -
        media.padding.top - media.padding.bottom -
        media.viewInsets.bottom - 44;
    final dialogHeight = available < 520 ? available : 520.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 390,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 10, 5),
              child: Row(children: [
                const Expanded(
                  child: Text(
                    '거치폰 연결 관리',
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: RemoteControl.instance.station.snapshots(),
                builder: (context, stationSnap) {
                  if (stationSnap.hasError) {
                    return _panel(details: Text(
                      '기기 상태를 읽을 수 없습니다: ' +
                      stationSnap.error.toString()));
                  }
                  if (!stationSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final station = stationSnap.data!.data() ?? {};
                  final paired =
                      (station['viewerUid'] as String? ?? '').isNotEmpty;
                  if (paired) {
                    return _panel(
                      details: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.verified_user_outlined,
                              color: Colors.green, size: 28),
                          const SizedBox(height: 12),
                          const Text(
                            '연결된 뷰어폰',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(station['viewerEmail'] as String? ??
                              '이메일 미확인'),
                          const SizedBox(height: 16),
                          const Text(
                            '연결 해제 시 해당 계정의 영상·제어 접근을 차단합니다.',
                            style: TextStyle(fontSize: 12),
                          ),
                          if (_error != null) Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                      footer: OutlinedButton(
                        onPressed: _busy ? null : () => _perform(() async {
                          await widget.stopStream();
                          await RemoteControl.instance.revokeViewer();
                          _renew();
                        }),
                        child: const Text('뷰어 연결 해제'),
                      ),
                    );
                  }
                  return FutureBuilder<
                      DocumentReference<Map<String, dynamic>>?>(
                    future: _invite,
                    builder: (context, inviteSnap) =>
                        _buildUnpaired(inviteSnap),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The owner signs in with email/password, not with the station's anonymous
/// identity. Revoked users fail the server-side Firestore access check.
class ViewerPairingGate extends StatefulWidget {
  const ViewerPairingGate({
    super.key,
    required this.viewerBuilder,
    this.accessCheck,
  });
  final WidgetBuilder viewerBuilder;
  /// Optional injection for widget tests; production uses Firebase grants.
  final Future<bool> Function()? accessCheck;

  @override
  State<ViewerPairingGate> createState() => _ViewerPairingGateState();
}

class _ViewerPairingGateState extends State<ViewerPairingGate> {
  late Future<bool> _hasAccess;

  @override
  void initState() {
    super.initState();
    _hasAccess =
        widget.accessCheck?.call() ?? RemoteControl.instance.viewerHasAccess();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _hasAccess,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(appBar: AppBar(title: const Text('연결 확인')),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('네트워크 연결을 확인해 주세요: ${snapshot.error}'),
            TextButton(onPressed: () => setState(() {
              _hasAccess = widget.accessCheck?.call() ??
                  RemoteControl.instance.viewerHasAccess();
            }), child: const Text('다시 시도')),
          ])));
      }
      if (!snapshot.hasData) return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
      if (snapshot.data == true) return widget.viewerBuilder(context);
      return ViewerPairingScreen(onPaired: () {
        // setState must be synchronous (a Future-returning expression causes
        // Flutter's "callback argument returned a Future" runtime error).
        setState(() {
          _hasAccess = Future<bool>.value(true);
        });
      });
    },
  );
}

class ViewerPairingScreen extends StatefulWidget {
  const ViewerPairingScreen({super.key, required this.onPaired});
  final VoidCallback onPaired;

  @override
  State<ViewerPairingScreen> createState() => _ViewerPairingScreenState();
}

class _ViewerPairingScreenState extends State<ViewerPairingScreen> {
  final _code = TextEditingController();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _listener;
  DocumentReference<Map<String, dynamic>>? _pendingRef;
  Timer? _waitTimeout;
  bool _busy = false;
  bool _waiting = false;
  bool _approved = false;
  String? _error;

  Future<void> _scanQr() async {
    if (_busy || _waiting) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _HomeCamPairingQrScanner()),
    );
    if (!mounted || result == null) return;
    final code = HomeCamPairingQr.parse(result);
    if (code == null) {
      setState(() => _error = '켜봄 연결 QR코드가 아닙니다.');
      return;
    }
    _code.text = code;
    await _claim();
  }

  Future<void> _claim() async {
    if (_busy || _waiting) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ref = await RemoteControl.instance.requestPairing(_code.text);
      if (!mounted) return;
      setState(() => _waiting = true);
      _pendingRef = ref;
      _waitTimeout?.cancel();
      _waitTimeout = Timer(const Duration(minutes: 10), () {
        if (!mounted || _approved) return;
        _listener?.cancel();
        _pendingRef = null;
        setState(() {
          _waiting = false;
          _error = '연결 코드가 만료됐어요. 거치폰에서 새 코드를 만들어 주세요.';
        });
      });
      _listener = ref.snapshots().listen((snapshot) async {
        if (!mounted || _approved) return;
        final data = snapshot.data();
        if (data?['status'] != 'approved') return;
        _approved = true;
        _waitTimeout?.cancel();
        _pendingRef = null;
        try {
          await RemoteControl.instance.saveApprovedViewerPairing(ref);
          if (mounted) widget.onPaired();
        } catch (error) {
          _approved = false;
          if (mounted) setState(() {
            _error = '승인 확인 오류: $error';
            _waiting = false;
          });
        }
      }, onError: (Object error) {
        if (mounted) setState(() {
          _error = '연결 승인 대기 오류: $error';
          _waiting = false;
        });
      });
    } catch (error) {
      if (mounted) setState(() => _error = '기기 연결 오류: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _waitTimeout?.cancel();
    _listener?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('거치폰 연결')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.link_rounded, size: 42),
          const SizedBox(height: 16),
          const Text(
            '거치폰의 QR코드를 스캔하면 연결 요청이 자동으로 전송돼요.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('kyeobom-scan-pairing-qr'),
            onPressed: _busy || _waiting ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('QR코드 스캔'),
          ),
          const SizedBox(height: 14),
          const Text('또는 연결 코드 직접 입력',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 10,
            enabled: !_waiting,
            decoration: const InputDecoration(
              labelText: '연결 코드 (10자리)',
              hintText: 'ABCD2345JK',
              counterText: '',
            ),
          ),
          if (_error != null) Text(_error!,
              style: const TextStyle(color: Colors.red)),
          if (_waiting) const Text(
            '거치폰에서 연결 요청을 승인해 주세요. 승인 전에는 영상에 접근할 수 없습니다.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy || _waiting ? null : _claim,
            child: Text(_waiting ? '승인 대기 중' : _busy ? '확인 중...' : '연결 요청'),
          ),
          if (_waiting) TextButton(
            onPressed: () async {
              _waitTimeout?.cancel();
              await _listener?.cancel();
              _listener = null;
              final invitation = _pendingRef;
              _pendingRef = null;
              if (invitation != null) {
                try {
                  await RemoteControl.instance.cancelPairingRequest(invitation);
                } catch (_) {
                  // The station may have approved or expired the claim.
                }
              }
              if (mounted) setState(() {
                _waiting = false;
                _error = null;
              });
            },
            child: const Text('요청 대기 취소'),
          ),
        ]),
      ),
    ))),
  );
}


/// This camera only reads a short-lived invitation code. It does not start
/// the home-camera stream and cannot approve access on the station's behalf.
class _HomeCamPairingQrScanner extends StatefulWidget {
  const _HomeCamPairingQrScanner();

  @override
  State<_HomeCamPairingQrScanner> createState() =>
      _HomeCamPairingQrScannerState();
}

class _HomeCamPairingQrScannerState extends State<_HomeCamPairingQrScanner> {
  final MobileScannerController _controller =
      MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final code = HomeCamPairingQr.parse(barcode.rawValue);
      if (code == null) continue;
      _handled = true;
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('켜봄 QR코드 스캔')),
        body: SafeArea(
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '거치폰 화면에 표시된 QR코드를 카메라에 맞춰 주세요.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'QR 스캔 카메라를 열 수 없습니다. 카메라 권한을 확인하거나 '
                        '연결 코드를 직접 입력해 주세요.\n$error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '기기 연결 QR코드 이외의 코드는 무시합니다.\n'
                '스캔 후에도 거치폰에서 연결 승인이 필요합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),
      );
}
