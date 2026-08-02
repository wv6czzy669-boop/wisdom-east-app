// Build 26 Phase 4B-1: CloudKitBridgeInfo -- wire parsing, fail-closed
// behavior, and the private-only cross-check against Phase 4A's domain
// constants.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';

void main() {
  Map<Object?, Object?> valid() => {
        'bridgeVersion': 1,
        'expectedZoneName': 'EASTKeptZone',
        'expectedRecordTypes': ['CKKeptWisdom', 'CKEastSyncState'],
        'privateDatabaseOnly': true,
        'capabilityActivationExpected': false,
      };

  group('1. a valid bridge-info payload parses correctly', () {
    test('parses all fields', () {
      final info = CloudKitBridgeInfo.tryParse(valid());
      expect(info, isNotNull);
      expect(info!.bridgeVersion, 1);
      expect(info.expectedZoneName, 'EASTKeptZone');
      expect(info.expectedRecordTypes, ['CKKeptWisdom', 'CKEastSyncState']);
      expect(info.privateDatabaseOnly, isTrue);
      expect(info.capabilityActivationExpected, isFalse);
    });
  });

  group(
      '2. bridge info validates expected private-only boundaries '
      '(matchesPhase4ADomainConstants)', () {
    test('a correctly-reported bridge matches the Phase 4A constants', () {
      final info = CloudKitBridgeInfo.tryParse(valid())!;
      expect(info.matchesPhase4ADomainConstants(), isTrue);
    });

    test('a mismatched zone name fails the cross-check', () {
      final raw = valid()..['expectedZoneName'] = 'SomeOtherZone';
      final info = CloudKitBridgeInfo.tryParse(raw)!;
      expect(info.matchesPhase4ADomainConstants(), isFalse);
    });

    test('a missing expected record type fails the cross-check', () {
      final raw = valid()..['expectedRecordTypes'] = ['CKKeptWisdom'];
      final info = CloudKitBridgeInfo.tryParse(raw)!;
      expect(info.matchesPhase4ADomainConstants(), isFalse);
    });

    test('privateDatabaseOnly=false fails the cross-check', () {
      final raw = valid()..['privateDatabaseOnly'] = false;
      final info = CloudKitBridgeInfo.tryParse(raw)!;
      expect(info.matchesPhase4ADomainConstants(), isFalse);
    });

    test(
        'capabilityActivationExpected is always false in Phase 4B-1 -- a '
        'true value here would signal Phase 4B-2 has already begun', () {
      final info = CloudKitBridgeInfo.tryParse(valid())!;
      expect(info.capabilityActivationExpected, isFalse);
    });
  });

  group('3. malformed bridge info fails closed', () {
    test('missing bridgeVersion fails closed', () {
      final raw = valid()..remove('bridgeVersion');
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('bridgeVersion below 1 fails closed', () {
      final raw = valid()..['bridgeVersion'] = 0;
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('an empty expectedZoneName fails closed', () {
      final raw = valid()..['expectedZoneName'] = '';
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('a non-list expectedRecordTypes fails closed', () {
      final raw = valid()..['expectedRecordTypes'] = 'CKKeptWisdom';
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('an empty expectedRecordTypes list fails closed', () {
      final raw = valid()..['expectedRecordTypes'] = <String>[];
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('a non-string entry in expectedRecordTypes fails closed', () {
      final raw = valid()..['expectedRecordTypes'] = ['CKKeptWisdom', 7];
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('missing privateDatabaseOnly fails closed', () {
      final raw = valid()..remove('privateDatabaseOnly');
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });

    test('missing capabilityActivationExpected fails closed', () {
      final raw = valid()..remove('capabilityActivationExpected');
      expect(CloudKitBridgeInfo.tryParse(raw), isNull);
    });
  });

  test('expectedRecordTypes is unmodifiable', () {
    final info = CloudKitBridgeInfo.tryParse(valid())!;
    expect(() => info.expectedRecordTypes.add('x'), throwsUnsupportedError);
  });

  test('equality and hashCode are field-based', () {
    final a = CloudKitBridgeInfo.tryParse(valid())!;
    final b = CloudKitBridgeInfo.tryParse(valid())!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
