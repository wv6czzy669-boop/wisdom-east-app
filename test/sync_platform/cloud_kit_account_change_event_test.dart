// Build 26 Phase 4B-1: CloudKitAccountChangeEvent -- content-free event
// parsing and fail-closed behavior tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';

void main() {
  group(
      '1. account-change events contain no account or user content -- the '
      'type itself has no field that could hold any', () {
    test('a valid event parses to the accountChanged kind', () {
      final event =
          CloudKitAccountChangeEvent.tryParse({'event': 'accountChanged'});
      expect(event, isNotNull);
      expect(event!.kind, CloudKitAccountChangeEventKind.accountChanged);
    });

    test('toString never contains anything beyond the kind name', () {
      final event =
          CloudKitAccountChangeEvent.tryParse({'event': 'accountChanged'})!;
      expect(event.toString(), 'CloudKitAccountChangeEvent(accountChanged)');
    });
  });

  group('2. malformed or unrecognized events fail closed (return null)', () {
    test('a non-Map payload fails closed', () {
      expect(CloudKitAccountChangeEvent.tryParse('accountChanged'), isNull);
      expect(CloudKitAccountChangeEvent.tryParse(null), isNull);
      expect(CloudKitAccountChangeEvent.tryParse(42), isNull);
    });

    test('a missing event key fails closed', () {
      expect(CloudKitAccountChangeEvent.tryParse(<String, Object?>{}), isNull);
    });

    test('an unrecognized event value fails closed', () {
      expect(
        CloudKitAccountChangeEvent.tryParse({'event': 'somethingElse'}),
        isNull,
      );
    });

    test('a wrong-typed event value fails closed', () {
      expect(CloudKitAccountChangeEvent.tryParse({'event': 42}), isNull);
    });
  });

  test('equality and hashCode are kind-based', () {
    final a = CloudKitAccountChangeEvent.tryParse({'event': 'accountChanged'})!;
    final b = CloudKitAccountChangeEvent.tryParse({'event': 'accountChanged'})!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
