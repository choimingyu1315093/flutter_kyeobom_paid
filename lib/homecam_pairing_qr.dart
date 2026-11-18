/// Encodes only a short-lived invitation code: never a UID, credential,
/// email address, or any persistent access token.
abstract final class HomeCamPairingQr {
  static const prefix = 'kyeobom:pair:v1:';
  static final RegExp _code = RegExp(r'^[A-HJ-NP-Z2-9]{10}$');

  static String encode(String code) {
    final normalized = code.trim().toUpperCase();
    if (!_code.hasMatch(normalized)) {
      throw FormatException('잘못된 기기 연결 코드입니다.');
    }
    return '$prefix$normalized';
  }

  /// Only first-party versioned payloads or a bare 10-character code.
  /// Do not follow external URLs, deep links, or Firebase document paths.
  static String? parse(String? scanned) {
    if (scanned == null) return null;
    final value = scanned.trim();
    final raw = value.startsWith(prefix)
        ? value.substring(prefix.length) : value;
    final code = raw.toUpperCase();
    return _code.hasMatch(code) ? code : null;
  }
}
