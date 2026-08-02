// Build 26 Phase 4B-1: MethodChannelCloudKitPlatformBridge -- exact channel
// contract, malformed-result fail-closed behavior, and safe error mapping.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_error.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/method_channel_cloud_kit_platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel =
      MethodChannel(MethodChannelCloudKitPlatformBridge.methodChannelName);
  const eventChannel =
      EventChannel(MethodChannelCloudKitPlatformBridge.eventChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void setMethodHandler(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(methodChannel, handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  const bridge = MethodChannelCloudKitPlatformBridge();

  Map<String, Object?> validSnapshot() => {
        'status': 'available',
        'isPrivateDatabaseUsable': true,
        'accountFingerprint': 'deadbeef',
        'fingerprintResolved': true,
        'bridgeVersion': 1,
      };

  Map<String, Object?> validZoneResult() => {
        'success': true,
        'zoneCreated': true,
        'zoneAlreadyExisted': false,
        'accountStatus': 'available',
        'errorCode': null,
      };

  Map<String, Object?> validBridgeInfo() => {
        'bridgeVersion': 1,
        'expectedZoneName': 'EASTKeptZone',
        'expectedRecordTypes': ['CKKeptWisdom', 'CKEastSyncState'],
        'privateDatabaseOnly': true,
        'capabilityActivationExpected': false,
      };

  group('1. channel method names and channel names remain exact', () {
    test('methodChannelName and eventChannelName are the documented values',
        () {
      expect(
        MethodChannelCloudKitPlatformBridge.methodChannelName,
        'com.dogukan.dailywisdom/cloudkit_sync',
      );
      expect(
        MethodChannelCloudKitPlatformBridge.eventChannelName,
        'com.dogukan.dailywisdom/cloudkit_sync_events',
      );
    });

    test('getAccountSnapshot invokes the exact method name', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return validSnapshot();
      });
      await bridge.getAccountSnapshot();
      expect(captured!.method, 'getAccountSnapshot');
    });

    test('configurePrivateZone invokes the exact method name', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return validZoneResult();
      });
      await bridge.configurePrivateZone();
      expect(captured!.method, 'configurePrivateZone');
    });

    test('getBridgeInfo invokes the exact method name', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return validBridgeInfo();
      });
      await bridge.getBridgeInfo();
      expect(captured!.method, 'getBridgeInfo');
    });
  });

  group('2. a valid native result parses successfully', () {
    test('getAccountSnapshot', () async {
      setMethodHandler((call) async => validSnapshot());
      final snapshot = await bridge.getAccountSnapshot();
      expect(snapshot.accountFingerprint, 'deadbeef');
    });

    test('configurePrivateZone', () async {
      setMethodHandler((call) async => validZoneResult());
      final result = await bridge.configurePrivateZone();
      expect(result.success, isTrue);
    });

    test('getBridgeInfo', () async {
      setMethodHandler((call) async => validBridgeInfo());
      final info = await bridge.getBridgeInfo();
      expect(info.expectedZoneName, 'EASTKeptZone');
    });
  });

  group('3. malformed native results fail closed as CloudKitPlatformException',
      () {
    test('a non-Map result throws malformedResultCode', () async {
      setMethodHandler((call) async => 'not a map');
      await expectLater(
        bridge.getAccountSnapshot(),
        throwsA(
          isA<CloudKitPlatformException>().having(
            (e) => e.code,
            'code',
            CloudKitPlatformException.malformedResultCode,
          ),
        ),
      );
    });

    test('a null result throws malformedResultCode', () async {
      setMethodHandler((call) async => null);
      await expectLater(
        bridge.configurePrivateZone(),
        throwsA(isA<CloudKitPlatformException>()),
      );
    });

    test('a map missing required fields throws malformedResultCode', () async {
      setMethodHandler((call) async => <String, Object?>{'bridgeVersion': 1});
      await expectLater(
        bridge.getBridgeInfo(),
        throwsA(
          isA<CloudKitPlatformException>().having(
            (e) => e.code,
            'code',
            CloudKitPlatformException.malformedResultCode,
          ),
        ),
      );
    });
  });

  group(
      '4. native exceptions map to safe typed errors without forwarding '
      'localized messages', () {
    test('a PlatformException forwards only its symbolic code', () async {
      setMethodHandler((call) async {
        throw PlatformException(
          code: 'notAuthenticated',
          message: 'a localized CloudKit message that must never surface',
        );
      });
      await expectLater(
        bridge.getAccountSnapshot(),
        throwsA(
          isA<CloudKitPlatformException>()
              .having((e) => e.code, 'code', 'notAuthenticated')
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('localized')),
              ),
        ),
      );
    });

    test(
        'a MissingPluginException (no native handler registered) maps to '
        'noNativeHandlerCode', () async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await expectLater(
        bridge.getBridgeInfo(),
        throwsA(
          isA<CloudKitPlatformException>().having(
            (e) => e.code,
            'code',
            CloudKitPlatformException.noNativeHandlerCode,
          ),
        ),
      );
    });

    test(
        'a PlatformException with a blank code maps to unrecognizedNativeErrorCode',
        () async {
      setMethodHandler((call) async {
        throw PlatformException(code: '   ');
      });
      await expectLater(
        bridge.configurePrivateZone(),
        throwsA(
          isA<CloudKitPlatformException>().having(
            (e) => e.code,
            'code',
            CloudKitPlatformException.unrecognizedNativeErrorCode,
          ),
        ),
      );
    });
  });

  group('5. account-change events', () {
    test('a valid event is delivered', () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'event': 'accountChanged'});
          },
        ),
      );

      final event = await bridge.accountChangeEvents.first;
      expect(event.kind.name, 'accountChanged');
    });

    test('a malformed event is dropped, never surfaced as a stream error',
        () async {
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'event': 'somethingUnrecognized'});
            events.success({'event': 'accountChanged'});
          },
        ),
      );

      // The first (malformed) event must be silently skipped -- the first
      // *emitted* event this stream produces is the valid one.
      final event = await bridge.accountChangeEvents.first;
      expect(event.kind.name, 'accountChanged');
    });
  });

  group(
      '6. Phase 4C-2: existing three methods remain backward compatible '
      'after the two new argument-carrying methods were added', () {
    test(
        'getAccountSnapshot/configurePrivateZone/getBridgeInfo still '
        'invoke with no arguments', () async {
      final capturedArguments = <Object?>[];
      setMethodHandler((call) async {
        capturedArguments.add(call.arguments);
        switch (call.method) {
          case 'getAccountSnapshot':
            return validSnapshot();
          case 'configurePrivateZone':
            return validZoneResult();
          case 'getBridgeInfo':
            return validBridgeInfo();
        }
        return null;
      });

      await bridge.getAccountSnapshot();
      await bridge.configurePrivateZone();
      await bridge.getBridgeInfo();

      expect(capturedArguments, [null, null, null]);
    });
  });

  group('7. Phase 4C-2: modifyPrivateRecords/fetchPrivateZoneChanges wiring',
      () {
    test(
        'modifyPrivateRecords invokes the exact method name with the '
        'request arguments', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return {'overallStatus': 'allSucceeded', 'outcomes': <Object?>[]};
      });

      const request = CloudKitModifyRecordsRequest(records: []);
      final result = await bridge.modifyPrivateRecords(request);

      expect(captured!.method, 'modifyPrivateRecords');
      expect(captured!.arguments, isA<Map<Object?, Object?>>());
      expect(
        result.overallStatus,
        CloudKitModifyRecordsOverallStatus.allSucceeded,
      );
    });

    test(
        'fetchPrivateZoneChanges invokes the exact method name with the '
        'request arguments', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return {
          'outcome': 'success',
          'changedKeptWisdomRecords': <Object?>[],
          'changedSyncStateRecords': <Object?>[],
          'serverToken': 'token-1',
        };
      });

      const request = CloudKitZoneChangesRequest();
      final result = await bridge.fetchPrivateZoneChanges(request);

      expect(captured!.method, 'fetchPrivateZoneChanges');
      expect(
        (captured!.arguments as Map<Object?, Object?>)['previousServerToken'],
        isNull,
      );
      expect(result.outcome, CloudKitZoneChangesOutcome.success);
      expect(result.serverToken, 'token-1');
    });

    test('a malformed modifyPrivateRecords result throws malformedResultCode',
        () async {
      setMethodHandler((call) async => 'not a map');
      const request = CloudKitModifyRecordsRequest(records: []);
      await expectLater(
        bridge.modifyPrivateRecords(request),
        throwsA(
          isA<CloudKitPlatformException>().having(
            (e) => e.code,
            'code',
            CloudKitPlatformException.malformedResultCode,
          ),
        ),
      );
    });
  });
}
