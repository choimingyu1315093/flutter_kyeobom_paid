import 'package:flutter/material.dart';

import 'kyeobom_design.dart';

/// Confirms entering the unattended station mode. This dialog is entirely
/// presentational: camera, microphone, wakelock and Firebase are untouched.
Future<bool> showKyeobomStationStartDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _StationStartDialog(),
  );
  return accepted == true;
}

class _StationStartDialog extends StatelessWidget {
  const _StationStartDialog();

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: KyeobomPalette.bluePale,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.videocam_outlined,
                      size: 29,
                      color: KyeobomPalette.blue,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: KyeobomPalette.canvas,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'STANDBY',
                      style: TextStyle(
                        color: KyeobomPalette.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                const Text(
                  '홈캠 대기 모드가 시작됩니다.',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: KyeobomPalette.ink,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  '거치폰을 안전하게 준비해 주세요.',
                  style: TextStyle(
                    fontSize: 13, color: KyeobomPalette.muted,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.fromLTRB(15, 17, 15, 17),
                  decoration: BoxDecoration(
                    color: KyeobomPalette.canvas,
                    border: Border.all(color: KyeobomPalette.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WaitingGuide(
                        icon: Icons.dark_mode_outlined,
                        title: '어두운 대기 화면',
                        description: '화면은 어둡게 유지되며 자동으로 잠기지 않습니다.',
                      ),
                      SizedBox(height: 17),
                      Divider(color: KyeobomPalette.border, height: 1),
                      SizedBox(height: 17),
                      _WaitingGuide(
                        icon: Icons.power_outlined,
                        title: '충전기와 앱 실행 유지',
                        description:
                            '안정적인 원격 연결을 위해 충전기를 연결하고 앱을 실행 상태로 유지해 주세요.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined,
                        color: KyeobomPalette.blue, size: 17),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '연결을 기다리는 동안 카메라와 마이크는 꺼져 있습니다.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: KyeobomPalette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: const Text('대기 시작'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}

class _WaitingGuide extends StatelessWidget {
  const _WaitingGuide({
    required this.icon, required this.title, required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: KyeobomPalette.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: KyeobomPalette.navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: KyeobomPalette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                const SizedBox(height: 5),
                Text(description,
                    style: const TextStyle(
                      color: KyeobomPalette.muted,
                      fontSize: 12,
                      height: 1.45,
                    )),
              ],
            ),
          ),
        ],
      );
}
