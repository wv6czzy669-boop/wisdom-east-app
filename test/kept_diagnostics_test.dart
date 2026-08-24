import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/kept_diagnostics.dart';

void main() {
  test('debug diagnostic accepts ordinary and empty messages', () {
    expect(() => keptDiagnostic('stage-begin: some-stage'), returnsNormally);
    expect(() => keptDiagnostic(''), returnsNormally);
  });

  test('diagnostic log prefix remains stable for device capture', () {
    expect(keptDiagnosticLogPrefix, 'EAST_KEPT_DIAGNOSTIC');
  });

  test('tests exercise the debug logging path', () {
    expect(kDebugMode, isTrue);
  });
}
