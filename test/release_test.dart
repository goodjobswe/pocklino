import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/settings.dart';

void main() {
  test('The version shown in Settings is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(version, isNotNull, reason: 'pubspec.yaml needs a version line');
    expect(appVersion, version!.group(1));
  });
}
