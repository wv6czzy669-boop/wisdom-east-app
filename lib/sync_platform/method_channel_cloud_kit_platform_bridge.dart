import 'package:flutter/services.dart';

import 'cloud_kit_account_change_event.dart';
import 'cloud_kit_account_snapshot.dart';
import 'cloud_kit_bridge_info.dart';
import 'cloud_kit_delete_records_contract.dart';
import 'cloud_kit_kept_wisdom_record_names_contract.dart';
import 'cloud_kit_modify_records_contract.dart';
import 'cloud_kit_platform_bridge.dart';
import 'cloud_kit_platform_error.dart';
import 'cloud_kit_sync_state_epoch_contract.dart';
import 'cloud_kit_zone_changes_contract.dart';
import 'cloud_kit_zone_configuration_result.dart';

/// Build 26 Phase 4B-1: production [CloudKitPlatformBridge], backed by the
/// native Swift bridge registered in `ios/Runner/CloudKitSyncBridge.swift`
/// (see `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4B-1 section
/// for the exact channel contract). Follows this codebase's existing
/// `MethodChannelFileProtectionBridge` convention
/// (`lib/persistence/file_protection_bridge.dart`): never no-ops on a
/// platform with no native handler registered -- a missing handler
/// surfaces as a [CloudKitPlatformException], exactly like any other
/// failure.
///
/// No method here accepts, and no field on any type it returns can hold,
/// wisdom text, Reflection text, a `KeptRecord`-shaped value, or any
/// daily-access data -- this file imports nothing from
/// `lib/models/kept_record.dart` or any daily-access file (see
/// `test/sync_platform/cloud_kit_platform_privacy_test.dart` for the
/// enforced proof).
final class MethodChannelCloudKitPlatformBridge
    implements CloudKitPlatformBridge {
  const MethodChannelCloudKitPlatformBridge();

  static const String methodChannelName =
      'com.dogukan.dailywisdom/cloudkit_sync';
  static const String eventChannelName =
      'com.dogukan.dailywisdom/cloudkit_sync_events';

  static const String methodGetAccountSnapshot = 'getAccountSnapshot';
  static const String methodConfigurePrivateZone = 'configurePrivateZone';
  static const String methodGetBridgeInfo = 'getBridgeInfo';

  /// Build 26 Phase 4C-2. Existing method names above are unchanged and
  /// still take no arguments -- these two are the only methods on this
  /// channel that do.
  static const String methodModifyPrivateRecords = 'modifyPrivateRecords';
  static const String methodFetchPrivateZoneChanges = 'fetchPrivateZoneChanges';

  /// Build 26 Phase 5 (slice 2). Used only by the remote deletion runner
  /// (`lib/sync_deletion/`) -- never by `SyncOrchestrator` or
  /// `KeptSyncBootstrapCoordinator`.
  static const String methodFetchSyncStateEpoch = 'fetchSyncStateEpoch';
  static const String methodListKeptWisdomRecordNames =
      'listKeptWisdomRecordNames';
  static const String methodDeleteKeptWisdomRecords = 'deleteKeptWisdomRecords';

  static const MethodChannel _methodChannel = MethodChannel(methodChannelName);
  static const EventChannel _eventChannel = EventChannel(eventChannelName);

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    final raw = await _invoke(methodGetAccountSnapshot);
    final snapshot = _asMap(raw) == null
        ? null
        : CloudKitAccountSnapshot.tryParse(_asMap(raw)!);
    if (snapshot == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return snapshot;
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() async {
    final raw = await _invoke(methodConfigurePrivateZone);
    final result = _asMap(raw) == null
        ? null
        : CloudKitZoneConfigurationResult.tryParse(_asMap(raw)!);
    if (result == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return result;
  }

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() async {
    final raw = await _invoke(methodGetBridgeInfo);
    final info =
        _asMap(raw) == null ? null : CloudKitBridgeInfo.tryParse(_asMap(raw)!);
    if (info == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return info;
  }

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents async* {
    await for (final raw in _eventChannel.receiveBroadcastStream()) {
      final event = CloudKitAccountChangeEvent.tryParse(raw);
      // A malformed or unrecognized event is dropped, never surfaced as a
      // stream error and never crashes the listener -- fail closed by
      // omission, consistent with this design's other "skip the one bad
      // item, keep going" rules (design doc §2.8).
      if (event != null) {
        yield event;
      }
    }
  }

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) async {
    final raw = await _invokeWithArguments(
      methodModifyPrivateRecords,
      request.toChannelArguments(),
    );
    final map = _asMap(raw);
    if (map == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return CloudKitModifyRecordsResult.tryParse(map);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) async {
    final raw = await _invokeWithArguments(
      methodFetchPrivateZoneChanges,
      request.toChannelArguments(),
    );
    final map = _asMap(raw);
    if (map == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return CloudKitZoneChangesResult.tryParse(map);
  }

  @override
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() async {
    final raw = await _invoke(methodFetchSyncStateEpoch);
    final map = _asMap(raw);
    if (map == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return CloudKitSyncStateEpochResult.tryParse(map);
  }

  @override
  Future<CloudKitKeptWisdomRecordNamesResult>
      listKeptWisdomRecordNames() async {
    final raw = await _invoke(methodListKeptWisdomRecordNames);
    final map = _asMap(raw);
    if (map == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return CloudKitKeptWisdomRecordNamesResult.tryParse(map);
  }

  @override
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  ) async {
    final raw = await _invokeWithArguments(
      methodDeleteKeptWisdomRecords,
      request.toChannelArguments(),
    );
    final map = _asMap(raw);
    if (map == null) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.malformedResultCode,
      );
    }
    return CloudKitDeleteKeptWisdomRecordsResult.tryParse(map);
  }

  Map<Object?, Object?>? _asMap(Object? raw) {
    if (raw is Map<Object?, Object?>) return raw;
    return null;
  }

  Future<Object?> _invoke(String method) async {
    try {
      return await _methodChannel.invokeMethod(method);
    } on MissingPluginException {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.noNativeHandlerCode,
      );
    } on PlatformException catch (error) {
      final code = error.code.trim();
      throw CloudKitPlatformException(
        code.isEmpty
            ? CloudKitPlatformException.unrecognizedNativeErrorCode
            : code,
      );
    } catch (_) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.unrecognizedNativeErrorCode,
      );
    }
  }

  /// Build 26 Phase 4C-2: identical error handling to [_invoke], for the
  /// two methods that carry an argument payload. Kept as a separate,
  /// parallel helper (rather than adding an optional parameter to
  /// [_invoke]) so every one of the three existing, argument-less methods
  /// above is provably unchanged -- neither its call site nor this
  /// method's own body was touched by this phase.
  Future<Object?> _invokeWithArguments(
    String method,
    Map<Object?, Object?> arguments,
  ) async {
    try {
      return await _methodChannel.invokeMethod(method, arguments);
    } on MissingPluginException {
      // No native handler is registered for this channel at all --
      // distinct from a PlatformException, where a handler ran but
      // returned an error. See
      // ios/Runner/AppDelegate.swift's registerCloudKitSyncChannel.
      throw const CloudKitPlatformException(
        CloudKitPlatformException.noNativeHandlerCode,
      );
    } on PlatformException catch (error) {
      // Only the symbolic .code is ever forwarded -- .message may contain
      // a CloudKit-localized, unpredictable string and is never read here.
      final code = error.code.trim();
      throw CloudKitPlatformException(
        code.isEmpty
            ? CloudKitPlatformException.unrecognizedNativeErrorCode
            : code,
      );
    } catch (_) {
      throw const CloudKitPlatformException(
        CloudKitPlatformException.unrecognizedNativeErrorCode,
      );
    }
  }
}
