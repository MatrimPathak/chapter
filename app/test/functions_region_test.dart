import 'dart:io';

import 'package:chapter/app/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// A client calling a different region from the functions fails every call,
/// and only on a real backend.
void main() {
  test('the app calls the region the functions deploy to', () {
    final source = File('../functions/src/shared/region.ts').readAsStringSync();
    final deployed = RegExp(r'REGION = "([^"]+)"').firstMatch(source)!.group(1);
    expect(functionsRegion, deployed);
  });
}
