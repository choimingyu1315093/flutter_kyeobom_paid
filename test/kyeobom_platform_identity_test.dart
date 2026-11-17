import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expected = 'com.mingyu.kyeobom';

  test('Android Gradle application ID and namespace match production', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('namespace = "$expected"'));
    expect(gradle, contains('applicationId = "$expected"'));

    final source = File(
      'android/app/src/main/kotlin/com/mingyu/kyeobom/MainActivity.kt',
    );
    expect(source.existsSync(), isTrue);
    final kotlin = source.readAsStringSync();
    expect(kotlin, startsWith('package $expected'));
    expect(kotlin, contains('"getViewerLandscapeSide"'));
    expect(kotlin, contains('"enableWaitingMode"'));
  });

  test('iOS Runner and test target bundle IDs match in all configurations', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(RegExp('PRODUCT_BUNDLE_IDENTIFIER = $expected;')
        .allMatches(project).length, 3);
    expect(RegExp('PRODUCT_BUNDLE_IDENTIFIER = $expected.RunnerTests;')
        .allMatches(project).length, 3);
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(info, contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)'));
  });

  test('Google real app IDs remain platform specific', () {
    final android = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    expect(android, contains(
      'ca-app-pub-5893975529562336~4819053037',
    ));
    expect(ios, contains(
      'ca-app-pub-5893975529562336~6718137266',
    ));
  });
}
