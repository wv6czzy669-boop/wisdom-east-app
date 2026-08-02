// Build 26 Phase 4B-1: CloudKitZoneConfigurationResult -- wire parsing and
// fail-closed behavior tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

void main() {
  Map<Object?, Object?> validCreated() => {
        'success': true,
        'zoneCreated': true,
        'zoneAlreadyExisted': false,
        'accountStatus': 'available',
        'errorCode': null,
      };

  Map<Object?, Object?> validAlreadyExisted() => {
        'success': true,
        'zoneCreated': false,
        'zoneAlreadyExisted': true,
        'accountStatus': 'available',
        'errorCode': null,
      };

  Map<Object?, Object?> validFailure() => {
        'success': false,
        'zoneCreated': false,
        'zoneAlreadyExisted': false,
        'accountStatus': 'noAccount',
        'errorCode': 'notAuthenticated',
      };

  group('1. valid results parse correctly', () {
    test('a newly created zone parses', () {
      final result = CloudKitZoneConfigurationResult.tryParse(validCreated());
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.zoneCreated, isTrue);
      expect(result.zoneAlreadyExisted, isFalse);
      expect(result.accountAvailability, CloudKitAccountAvailability.available);
      expect(result.errorCode, isNull);
    });

    test('an already-existing zone is treated as success', () {
      final result =
          CloudKitZoneConfigurationResult.tryParse(validAlreadyExisted());
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.zoneAlreadyExisted, isTrue);
    });

    test('a failure result parses with a symbolic error code', () {
      final result = CloudKitZoneConfigurationResult.tryParse(validFailure());
      expect(result, isNotNull);
      expect(result!.success, isFalse);
      expect(result.errorCode, 'notAuthenticated');
      expect(
        result.accountAvailability,
        CloudKitAccountAvailability.noAccount,
      );
    });
  });

  group('2. malformed results fail closed', () {
    test('missing success fails closed', () {
      final raw = validCreated()..remove('success');
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('claiming both zoneCreated and zoneAlreadyExisted fails closed', () {
      final raw = validCreated()..['zoneAlreadyExisted'] = true;
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('success=true with a non-null errorCode fails closed', () {
      final raw = validCreated()..['errorCode'] = 'somethingWrong';
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('success=false with a null errorCode fails closed', () {
      final raw = validFailure()..['errorCode'] = null;
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('success=false with zoneCreated=true fails closed', () {
      final raw = validFailure()..['zoneCreated'] = true;
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('an empty-string errorCode fails closed', () {
      final raw = validFailure()..['errorCode'] = '';
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });

    test('a wrong-typed accountStatus fails closed', () {
      final raw = validCreated()..['accountStatus'] = 7;
      expect(CloudKitZoneConfigurationResult.tryParse(raw), isNull);
    });
  });

  test('an unrecognized accountStatus wire value maps to unknown', () {
    final raw = validCreated()..['accountStatus'] = 'somethingNew';
    final result = CloudKitZoneConfigurationResult.tryParse(raw);
    expect(result!.accountAvailability, CloudKitAccountAvailability.unknown);
  });

  test('equality and hashCode are field-based', () {
    final a = CloudKitZoneConfigurationResult.tryParse(validCreated())!;
    final b = CloudKitZoneConfigurationResult.tryParse(validCreated())!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    final c = CloudKitZoneConfigurationResult.tryParse(validFailure())!;
    expect(a, isNot(c));
  });
}
