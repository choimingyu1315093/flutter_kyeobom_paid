/// Natural room audio and conservative Opus transport tuning.
/// These helpers are used ONLY by the independent audio WebRTC connection.
String tuneMonitoringOpus(String? sdp) {
  if (sdp == null || sdp.isEmpty) return sdp ?? '';
  final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(RegExp(r'\r?\n'));
  final opusPattern = RegExp(
    r'^a=rtpmap:(\d+) opus/48000(?:/\d+)?$',
    caseSensitive: false,
  );
  final index = lines.indexWhere((line) => opusPattern.hasMatch(line.trim()));
  if (index == -1) return sdp;
  final pt = opusPattern.firstMatch(lines[index].trim())!.group(1)!;
  final fmtpPattern = RegExp(r'^a=fmtp:' + pt + r'\s+(.+)$');
  final fmtpIndex = lines.indexWhere((line) => fmtpPattern.hasMatch(line));
  const tuning = <String, String>{
    'maxaveragebitrate': '48000',
    'useinbandfec': '1',
    'usedtx': '0',
  };
  if (fmtpIndex >= 0) {
    final values = <String, String>{};
    final params = fmtpPattern.firstMatch(lines[fmtpIndex])!.group(1)!;
    for (final item in params.split(';')) {
      final separator = item.indexOf('=');
      if (separator > 0) {
        values[item.substring(0, separator).trim().toLowerCase()] =
            item.substring(separator + 1).trim();
      }
    }
    values.addAll(tuning);
    lines[fmtpIndex] = 'a=fmtp:$pt ' +
        values.entries.map((e) => e.key + '=' + e.value).join(';');
  } else {
    lines.insert(
      index + 1,
      'a=fmtp:$pt ' +
          tuning.entries.map((e) => e.key + '=' + e.value).join(';'),
    );
  }
  return lines.join(newline);
}

/// Disables optional call-centric processing that may cause pumping/muffling
/// of faint room sounds. Unsupported options may be ignored by the SDK.
Map<String, dynamic> stationRoomAudioConstraints() => {
      'audio': {
        'optional': <Map<String, String>>[
          {'googEchoCancellation': 'false'},
          {'googEchoCancellation2': 'false'},
          {'googDAEchoCancellation': 'false'},
          {'googAutoGainControl': 'false'},
          {'googNoiseSuppression': 'false'},
          {'googHighpassFilter': 'false'},
          {'googTypingNoiseDetection': 'false'},
        ],
      },
      'video': false,
    };
