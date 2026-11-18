import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/remote_control.dart';

void main() {
  test('pairing code accepts harmless separators without losing entropy', () {
    expect(RemoteControl.normalizedCode('abcde-fghjk'), 'ABCDEFGHJK');
    expect(RemoteControl.normalizedCode('A B C D E F G H J K'),
        'ABCDEFGHJK');
  });

  test('pairing code does not silently truncate or rewrite invalid input', () {
    expect(RemoteControl.normalizedCode('ABCD!FGHJK'), contains('!'));
    expect(RemoteControl.normalizedCode('A0CDEFGHJK'), contains('0'));
    expect(RemoteControl.normalizedCode('ABCDEFGHJKL').length, 11);
  });
}
