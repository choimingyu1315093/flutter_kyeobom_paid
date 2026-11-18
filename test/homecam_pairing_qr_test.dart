import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/homecam_pairing_qr.dart';

void main() {
  test('QR payload encodes only a versioned short-lived pairing code', () {
    expect(HomeCamPairingQr.encode('ABCD2345JK'),
        'kyeobom:pair:v1:ABCD2345JK');
    expect(HomeCamPairingQr.parse('kyeobom:pair:v1:ABCD2345JK'),
        'ABCD2345JK');
    expect(HomeCamPairingQr.parse('abcd2345jk'), 'ABCD2345JK');
  });

  test('scanner never opens untrusted links or accepts invalid codes', () {
    for (final invalid in <String>[
      'https://example.com/kyeobom:pair:v1:ABCD2345JK',
      'kyeobom:pair:v2:ABCD2345JK',
      'kyeobom:pair:v1:ABCD2345JKextra',
      'kyeobom:pair:v1:ABCD2345J0',
      'ABCD2345J0', '123', ' ',
    ]) {
      expect(HomeCamPairingQr.parse(invalid), isNull, reason: invalid);
    }
    expect(() => HomeCamPairingQr.encode('invalid'), throwsFormatException);
    expect(HomeCamPairingQr.parse(null), isNull);
  });
}
