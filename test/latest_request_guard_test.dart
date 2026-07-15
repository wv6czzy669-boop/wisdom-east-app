import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/latest_request_guard.dart';

void main() {
  test('only the newest access refresh generation may commit', () {
    final guard = LatestRequestGuard();

    final olderRequest = guard.begin();
    final newerRequest = guard.begin();

    expect(guard.isCurrent(olderRequest), isFalse);
    expect(guard.isCurrent(newerRequest), isTrue);

    guard.invalidate();
    expect(guard.isCurrent(newerRequest), isFalse);
  });
}
