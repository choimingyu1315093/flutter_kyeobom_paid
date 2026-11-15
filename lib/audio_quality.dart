/// Conservative Opus tuning for the *independent audio-only* WebRTC peer.
///
/// - 48 kb/s cap supports natural room sound better than telephony bitrates.
/// - In-band FEC improves resilience to occasional packet loss.
/// - DTX disabled avoids dropping quiet room sounds entirely.
///
/// Does not change the already verified video SDP or force unsupported codecs.
/// If an Opus payload is absent or SDP is malformed, returns the source SDP.
String tuneMonitoringOpus(String? sdp) {
  if (sdp == null || sdp.isEmpty) return sdp ?? '';
  final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
  final original = sdp.split(RegExp(r'\r?\n'));
  final opusLine = RegExp(r'^a=rtpmap:(\d+) opus/48000(?:/\d+)?$', caseSensitive: false);
  final index = original.indexWhere((line) => opusLine.hasMatch(line.trim()));
  if (index < 0) return sdp;
  final pt = opusLine.firstMatch(original[index].trim())!.group(1)!;
  final fmtpRe = RegExp(r'^a=fmtp:' + pt + r'\s+(.+)
  final fmtpIndex = original.indexWhere((line) => fmtpRe.hasMatch(line));
  const tuning = <String,String>{
    'maxaveragebitrate':'48000',
    'useinbandfec':'1',
    'usedtx':'0',
  };
  if (fmtpIndex >= 0) {
    final match = fmtpRe.firstMatch(original[fmtpIndex])!;
    final values = <String,String>{};
    for (final item in match.group(1)!.split(';')) {
      final pair = item.trim().split('=');
      if (pair.length == 2 && pair[0].isNotEmpty) {
        values[pair[0].toLowerCase()] = pair[1];
      }
    }
    values.addAll(tuning);
    original[fmtpIndex] =
        'a=fmtp:$pt ' + values.entries.map((e) => '${e.key}=${e.value}').join(';');
  } else {
    original.insert(index + 1,
        'a=fmtp:$pt ' + tuning.entries.map((e) => '${e.key}=${e.value}').join(';'));
  }
  return original.join(newline);
}

/// Keep telephony voice processing from unintentionally flattening very soft
/// nearby sounds. Optional flags are non-fatal if a device ignores them.
Map<String, dynamic> stationRoomAudioConstraints() => {
  'audio': {
    'optional': <Map<String,String>>[
      {'googEchoCancellation':'false'},
      {'googEchoCancellation2':'false'},
      {'googDAEchoCancellation':'false'},
      {'googAutoGainControl':'false'},
      {'googNoiseSuppression':'false'},
      {'googHighpassFilter':'false'},
      {'googTypingNoiseDetection':'false'},
    ],
  },
  'video': false,
};
);
  final fmtpIndex = original.indexWhere((line) => fmtpRe.hasMatch(line));
  const tuning = <String,String>{
    'maxaveragebitrate':'48000',
    'useinbandfec':'1',
    'usedtx':'0',
  };
  if (fmtpIndex >= 0) {
    final match = fmtpRe.firstMatch(original[fmtpIndex])!;
    final values = <String,String>{};
    for (final item in match.group(1)!.split(';')) {
      final pair = item.trim().split('=');
      if (pair.length == 2 && pair[0].isNotEmpty) {
        values[pair[0].toLowerCase()] = pair[1];
      }
    }
    values.addAll(tuning);
    original[fmtpIndex] =
        'a=fmtp:$pt ' + values.entries.map((e) => '${e.key}=${e.value}').join(';');
  } else {
    original.insert(index + 1,
        'a=fmtp:$pt ' + tuning.entries.map((e) => '${e.key}=${e.value}').join(';'));
  }
  return original.join(newline);
}

/// Keep telephony voice processing from unintentionally flattening very soft
/// nearby sounds. Optional flags are non-fatal if a device ignores them.
Map<String, dynamic> stationRoomAudioConstraints() => {
  'audio': {
    'optional': <Map<String,String>>[
      {'googEchoCancellation':'false'},
      {'googEchoCancellation2':'false'},
      {'googDAEchoCancellation':'false'},
      {'googAutoGainControl':'false'},
      {'googNoiseSuppression':'false'},
      {'googHighpassFilter':'false'},
      {'googTypingNoiseDetection':'false'},
    ],
  },
  'video': false,
};
