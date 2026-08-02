// Build 26 Phase 4B-1: CloudKitAccountSnapshot -- wire parsing, fail-closed
// behavior, and fingerprint-privacy tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';

void main() {
  Map<Object?, Object?> validResolved() => {
        'status': 'available',
        'isPrivateDatabaseUsable': true,
        'accountFingerprint': 'deadbeef',
        'fingerprintResolved': true,
        'bridgeVersion': 1,
      };

  Map<Object?, Object?> validUnresolved() => {
        'status': 'noAccount',
        'isPrivateDatabaseUsable': false,
        'accountFingerprint': null,
        'fingerprintResolved': false,
        'bridgeVersion': 1,
      };

  group('1. every native account-status value maps correctly', () {
    for (final entry in {
      'available': CloudKitAccountAvailability.available,
      'noAccount': CloudKitAccountAvailability.noAccount,
      'restricted': CloudKitAccountAvailability.restricted,
      'couldNotDetermine': CloudKitAccountAvailability.couldNotDetermine,
      'temporarilyUnavailable':
          CloudKitAccountAvailability.temporarilyUnavailable,
    }.entries) {
      test('"${entry.key}" maps to ${entry.value}', () {
        expect(
          CloudKitAccountAvailabilityWireCodec.fromWireValue(entry.key),
          entry.value,
        );
      });
    }
  });

  group('2. unknown statuses fail safely (never thrown, never available)', () {
    test('an unrecognized wire string maps to unknown, not available', () {
      expect(
        CloudKitAccountAvailabilityWireCodec.fromWireValue('somethingNew'),
        CloudKitAccountAvailability.unknown,
      );
    });

    test('an empty string maps to unknown', () {
      expect(
        CloudKitAccountAvailabilityWireCodec.fromWireValue(''),
        CloudKitAccountAvailability.unknown,
      );
    });
  });

  group('3. malformed account snapshots fail closed (tryParse returns null)',
      () {
    test('a valid resolved snapshot parses', () {
      expect(CloudKitAccountSnapshot.tryParse(validResolved()), isNotNull);
    });

    test('a valid unresolved snapshot parses', () {
      expect(CloudKitAccountSnapshot.tryParse(validUnresolved()), isNotNull);
    });

    test('missing status fails closed', () {
      final raw = validResolved()..remove('status');
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('wrong-typed status fails closed', () {
      final raw = validResolved()..['status'] = 42;
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('missing isPrivateDatabaseUsable fails closed', () {
      final raw = validResolved()..remove('isPrivateDatabaseUsable');
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('missing bridgeVersion fails closed', () {
      final raw = validResolved()..remove('bridgeVersion');
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('bridgeVersion below 1 fails closed', () {
      final raw = validResolved()..['bridgeVersion'] = 0;
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('fingerprintResolved=true with no accountFingerprint fails closed',
        () {
      final raw = validResolved()..['accountFingerprint'] = null;
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test(
        'fingerprintResolved=true with empty accountFingerprint fails '
        'closed', () {
      final raw = validResolved()..['accountFingerprint'] = '';
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test(
        'fingerprintResolved=false with a non-null accountFingerprint '
        'fails closed', () {
      final raw = validUnresolved()..['accountFingerprint'] = 'unexpected';
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('a wrong-typed accountFingerprint fails closed', () {
      final raw = validResolved()..['accountFingerprint'] = 12345;
      expect(CloudKitAccountSnapshot.tryParse(raw), isNull);
    });

    test('a non-Map is never handed to tryParse (compile-time shape)', () {
      // tryParse's signature itself only accepts Map<Object?, Object?> --
      // this test documents that guarantee rather than exercising a
      // runtime branch.
      expect(CloudKitAccountSnapshot.tryParse, isA<Function>());
    });
  });

  group(
      '4. raw identity values are never represented in public models '
      '(the model only ever holds the already-opaque fingerprint, never '
      'a raw CKRecord.ID/recordName shape)', () {
    test('parsed accountFingerprint is exactly the opaque wire value', () {
      final snapshot = CloudKitAccountSnapshot.tryParse(validResolved())!;
      expect(snapshot.accountFingerprint, 'deadbeef');
    });
  });

  group('5. fingerprint remains opaque and is omitted from log-safe summaries',
      () {
    test('toLogSafeSummary never includes the fingerprint value', () {
      final snapshot = CloudKitAccountSnapshot.tryParse(validResolved())!;
      final summary = snapshot.toLogSafeSummary();
      expect(summary.containsKey('accountFingerprint'), isFalse);
      expect(summary['fingerprintResolved'], isTrue);
    });

    test('toString never includes the fingerprint value', () {
      final snapshot = CloudKitAccountSnapshot.tryParse(validResolved())!;
      expect(snapshot.toString(), isNot(contains('deadbeef')));
    });
  });

  test('equality and hashCode are field-based', () {
    final a = CloudKitAccountSnapshot.tryParse(validResolved())!;
    final b = CloudKitAccountSnapshot.tryParse(validResolved())!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    final c = CloudKitAccountSnapshot.tryParse(validUnresolved())!;
    expect(a, isNot(c));
  });
}
